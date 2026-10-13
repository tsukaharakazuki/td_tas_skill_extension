#!/usr/bin/env bash
# td-api.sh — curl だけで Treasure Data の REST API を呼ぶ最小クライアント。
#
# npm も外部ライブラリも使わない。通信先は Treasure Data のドメインだけ。
# 必要なもの: bash / curl（python3 があれば表形式で整形、無ければ JSON のまま表示）
#
#   ./td-api.sh status                       認証と疎通の確認（見えるDB数も表示）
#   ./td-api.sh databases                    DB 一覧
#   ./td-api.sh tables <db>                  テーブル一覧
#   ./td-api.sh describe <db> <table>        カラム定義
#   ./td-api.sh query <db> "<SQL>"           Trino で実行して結果を CSV 表示
#        [--engine presto|hive] [--max-rows N] [--out <file>] [--wait <秒>]
#   ./td-api.sh job-status <job_id>          ジョブの状態
#   ./td-api.sh job-result <job_id> [--max-rows N] [--out <file>]
#   ./td-api.sh parent-segments              CDP 親セグメント一覧
#   ./td-api.sh segments <parent_segment_id> CDP セグメント一覧
#   ./td-api.sh wf-projects                  ワークフローのプロジェクト一覧
#   ./td-api.sh wf-workflows <project_id>    プロジェクト内のワークフロー一覧
#   ./td-api.sh wf-attempts [件数]           直近の実行履歴
#   ./td-api.sh get <api|cdp|workflow> <path>  任意の GET（参照専用の逃げ道）
#
# 認証: <作業フォルダ>/tdx_key.txt（1行目 API キー / 2行目 リージョン）
#   作業フォルダは TD_WORKDIR > スクリプトと同階層 > $HOME/mnt 配下 の順で探す。
#   環境変数 TDX_API_KEY / TDX_SITE が設定済みならそちらを優先する。
#
# 安全上の決まり:
#   - API キーはコマンドライン引数に載せない（ps で見えない）。curl には -K でプロセス置換経由で渡す
#   - 通信は https のみ。宛先はリージョンごとの *.treasuredata.com / *.treasuredata.co.jp に固定
#   - 作業フォルダの tdx_policy.conf（setup-tdx.sh policy set で作る）の操作範囲に従う。
#     data / workflow / cdp の水準（none / read / write）を見て、範囲外の操作は実行しない。
#     ポリシーファイルが無い場合は status 以外を拒否する
#   - 書き込み系 SQL は data=write かつ TD_ALLOW_WRITE=1（ユーザーの了承を得た印）のときだけ通す
#   - 判定結果は tdx_audit.log に残す
#   - --check <コマンド...> で判定だけ表示する（実行しない）

set -uo pipefail

die() { echo "error: $*" >&2; exit 1; }

# ---------- 認証情報 ----------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
CHECK_ONLY=0
[ "${1:-}" = "--check" ] && { CHECK_ONLY=1; shift; }
if [ -z "${TD_WORKDIR:-}" ] && [ -f "$SCRIPT_DIR/tdx_policy.conf" ]; then TD_WORKDIR="$SCRIPT_DIR"; fi
if [ -z "${TDX_API_KEY:-}" ]; then
  if [ -z "${TD_WORKDIR:-}" ]; then
    if [ -s "$SCRIPT_DIR/tdx_key.txt" ]; then
      TD_WORKDIR="$SCRIPT_DIR"
    else
      _found="$(find "$HOME/mnt" -maxdepth 4 -name 'tdx_key.txt' -size +0 2>/dev/null | head -1)"
      [ -n "$_found" ] && TD_WORKDIR="$(dirname "$_found")"
    fi
  fi
  [ -n "${TD_WORKDIR:-}" ] && [ -s "$TD_WORKDIR/tdx_key.txt" ] \
    || die "tdx_key.txt が見つかりません。TD_WORKDIR=<作業フォルダ> を指定してください"
  TDX_API_KEY="$(sed -n '1p' "$TD_WORKDIR/tdx_key.txt" | tr -d '[:space:]')"
  if [ -z "${TDX_SITE:-}" ]; then
    TDX_SITE="$(sed -n '2p' "$TD_WORKDIR/tdx_key.txt" | tr -d '[:space:]')"
  fi
fi
[ -n "${TDX_API_KEY:-}" ] || die "API キーが空です"
TDX_SITE="$(printf '%s' "${TDX_SITE:-us01}" | tr '[:upper:]' '[:lower:]')"

case "$TDX_SITE" in
  us01|"")   API=api.treasuredata.com        CDP=api-cdp.treasuredata.com        WF=api-workflow.treasuredata.com ;;
  ap01|jp01) API=api.treasuredata.co.jp      CDP=api-cdp.treasuredata.co.jp      WF=api-workflow.treasuredata.co.jp ;;
  eu01)      API=api.eu01.treasuredata.com   CDP=api-cdp.eu01.treasuredata.com   WF=api-workflow.eu01.treasuredata.com ;;
  ap02)      API=api.ap02.treasuredata.com   CDP=api-cdp.ap02.treasuredata.com   WF=api-workflow.ap02.treasuredata.com ;;
  *) die "未知のリージョン: ${TDX_SITE}（us01 / ap01 / eu01 / ap02）" ;;
esac

HAS_PY=0; command -v python3 >/dev/null 2>&1 && HAS_PY=1
TMPD="$(mktemp -d)"; trap 'rm -rf "$TMPD"' EXIT
chmod 700 "$TMPD"

# ---------- HTTP ----------
# http <METHOD> <host> <path> [curl追加引数...]  → 本文を $TMPD/body、ステータスを標準出力
http() {
  local method="$1" host="$2" path="$3"; shift 3
  case "$host" in *.treasuredata.com|*.treasuredata.co.jp) ;; *) die "許可されていない宛先: $host" ;; esac
  curl -sS --proto '=https' --tlsv1.2 --max-time 120 \
    -K <(printf 'header = "Authorization: TD1 %s"\n' "$TDX_API_KEY") \
    -H 'Accept: application/json' -A 'td-api.sh/1.0' \
    -X "$method" -o "$TMPD/body" -w '%{http_code}' "$@" "https://$host$path"
}

# 成功(2xx)なら本文を出力、失敗ならエラー表示して終了
call() {
  local code
  code="$(http "$@")" || die "接続できませんでした（$2）。ネットワーク許可に *.treasuredata.com / *.treasuredata.co.jp があるか確認してください"
  case "$code" in
    2*) cat "$TMPD/body" ;;
    401) die "認証失敗 (401)。キーかリージョン（現在: ${TDX_SITE}）を確認してください" ;;
    403) die "権限不足 (403): $(head -c 400 "$TMPD/body")" ;;
    *)   die "HTTP $code: $(head -c 400 "$TMPD/body")" ;;
  esac
}

# fmt <kind>  標準入力の JSON を表に整形（python3 が無ければそのまま）
fmt() {
  if [ "$HAS_PY" = 0 ]; then cat; echo; return; fi
  python3 -c '
import json, sys
kind = sys.argv[1]
raw = sys.stdin.read()
if not raw.strip():
    sys.exit(1)
d = json.loads(raw)
def table(rows, cols):
    print("\t".join(cols))
    for r in rows:
        print("\t".join("" if r.get(c) is None else str(r.get(c)) for c in cols))
if kind == "databases":
    table(d.get("databases", []), ["name", "count", "updated_at"])
elif kind == "tables":
    table(d.get("tables", []), ["name", "type", "count", "updated_at"])
elif kind == "describe":
    cols = json.loads(d.get("schema") or "[]")
    print("column\ttype")
    for c in cols:
        print(f"{c[0]}\t{c[1]}")
    print("# rows: %s" % d.get("count"))
elif kind == "segments":
    rows = d if isinstance(d, list) else d.get("data", d.get("segments", []))
    table(rows, ["id", "name", "population", "updatedAt"])
elif kind == "wf-projects":
    table(d.get("projects", []), ["id", "name", "revision", "updatedAt"])
elif kind == "wf-workflows":
    table(d.get("workflows", []), ["id", "name", "revision"])
elif kind == "wf-attempts":
    rows = []
    for a in d.get("attempts", []):
        rows.append({"id": a.get("id"), "project": (a.get("project") or {}).get("name"),
                     "workflow": (a.get("workflow") or {}).get("name"),
                     "status": a.get("status") or ("success" if a.get("success") else ("running" if not a.get("done") else "error")),
                     "createdAt": a.get("createdAt")})
    table(rows, ["id", "project", "workflow", "status", "createdAt"])
else:
    json.dump(d, sys.stdout, ensure_ascii=False, indent=2); print()
' "$1"
}

# ---------- SQL ガード ----------
is_readonly_sql() {
  # コメントを除いて1行にし、先頭キーワードと危険語を調べる（保守的に判定する）
  local s
  s="$(sed -e 's/--.*$//' | tr '\n' ' ' | sed -E 's#/\*([^*]|\*+[^*/])*\*+/# #g' | tr '[:lower:]' '[:upper:]')"
  printf '%s' "$s" | grep -Eq '^[[:space:](]*(SELECT|WITH|SHOW|DESCRIBE|DESC|EXPLAIN|VALUES)[[:space:]]' || return 1
  printf '%s' "$s" | grep -Eqw 'INSERT|DELETE|DROP|CREATE|ALTER|UPDATE|MERGE|TRUNCATE|GRANT|REVOKE|CALL|OVERWRITE' && return 1
  return 0
}

# ---------- ジョブ結果 ----------
show_result() {
  local id="$1" max="$2" out="$3"
  local code
  code="$(http GET "$API" "/v3/job/result/$id?format=csv")" || die "結果を取得できませんでした"
  [ "${code:0:1}" = 2 ] || die "HTTP $code: $(head -c 400 "$TMPD/body")"
  mv "$TMPD/body" "$TMPD/result.csv"
  # 列名は job/show の hive_result_schema から付ける
  local header=""
  if [ "$HAS_PY" = 1 ]; then
    header="$(call GET "$API" "/v3/job/show/$id" | python3 -c '
import json, sys, csv, io
d = json.load(sys.stdin)
cols = json.loads(d.get("hive_result_schema") or "[]")
b = io.StringIO(); csv.writer(b).writerow([c[0] for c in cols]); print(b.getvalue().strip())')"
  fi
  local total; total="$(wc -l < "$TMPD/result.csv" | tr -d ' ')"
  if [ -n "$out" ]; then
    { [ -n "$header" ] && echo "$header"; cat "$TMPD/result.csv"; } > "$out"
    echo "# $total 行を $out に保存しました（job ${id}）"
  else
    [ -n "$header" ] && echo "$header"
    head -n "$max" "$TMPD/result.csv"
    [ "$total" -gt "$max" ] && echo "# 先頭 $max / $total 行を表示（全件は --out <file>）"
    echo "# job $id"
  fi
}

# ---------- コマンド ----------
cmd="${1:-help}"; shift || true

# ---------- 操作範囲の判定 ----------
POLICY="${TD_WORKDIR:-$SCRIPT_DIR}/tdx_policy.conf"
pol() {
  local v=""; [ -f "$POLICY" ] && v="$(sed -n "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*\([a-z]*\).*/\1/p" "$POLICY" | tail -1)"
  case "$v" in read|write) echo "$v" ;; *) echo none ;; esac
}
rank() { case "$1" in write) echo 2 ;; read) echo 1 ;; *) echo 0 ;; esac; }
CAT=""; LVL=read
case "$cmd" in
  status|help|-h|--help) CAT=always ;;
  databases|tables|describe|job-status|job-result) CAT=data ;;
  query) CAT=data; printf '%s' "${2:-}" | is_readonly_sql || LVL=write ;;
  parent-segments|segments) CAT=cdp ;;
  wf-projects|wf-workflows|wf-attempts) CAT=workflow ;;
  get) case "${1:-}" in api) CAT=data ;; cdp) CAT=cdp ;; workflow) CAT=workflow ;; *) CAT=always ;; esac ;;
  *) CAT=always ;;   # 不明なコマンドは下の case で弾かれる
esac
DECISION=allow; REASON=""
if [ "$CAT" != always ]; then
  if [ ! -f "$POLICY" ]; then DECISION=deny; REASON="tdx_policy.conf がありません。setup-tdx.sh policy で操作範囲を設定してください"
  elif [ "$(rank "$(pol "$CAT")")" -lt "$(rank "$LVL")" ]; then DECISION=deny; REASON="操作範囲外: $CAT は '$(pol "$CAT")' まで（この操作は ${LVL}）"
  elif [ "$LVL" = write ] && [ "${TD_ALLOW_WRITE:-0}" != 1 ]; then DECISION=deny; REASON="書き込み操作です。ユーザーの了承を得てから TD_ALLOW_WRITE=1 を付けて再実行してください"
  fi
fi
if [ $CHECK_ONLY = 1 ]; then printf '%s\t%s/%s\t%s\n' "$DECISION" "$CAT" "$LVL" "$REASON"; [ "$DECISION" = allow ]; exit $?; fi
if [ "$CAT" != always ]; then
  printf '%s\t%s\t%s/%s\ttd-api.sh %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$DECISION" "$CAT" "$LVL" \
    "$(printf '%s ' "$cmd" "$@" | tr '\n' ' ' | cut -c1-500)" >> "${TD_WORKDIR:-$SCRIPT_DIR}/tdx_audit.log" 2>/dev/null
fi
[ "$DECISION" = allow ] || die "$REASON"

case "$cmd" in
  status)
    echo "site: $TDX_SITE ($API)"
    echo "key length: ${#TDX_API_KEY}"
    dbs="$(call GET "$API" /v3/database/list)" || exit 1
    n="$(printf '%s' "$dbs" | { [ "$HAS_PY" = 1 ] && python3 -c 'import json,sys; print(len(json.load(sys.stdin).get("databases",[])))' || grep -o '"name"' | wc -l; })"
    echo "auth: OK（見えるデータベース: $n 件）"
    ;;
  databases)  call GET "$API" /v3/database/list | fmt databases ;;
  tables)     [ $# -ge 1 ] || die "usage: tables <db>"
              call GET "$API" "/v3/table/list/$1" | fmt tables ;;
  describe)   [ $# -ge 2 ] || die "usage: describe <db> <table>"
              call GET "$API" "/v3/table/show/$1/$2" | fmt describe ;;
  query)
    [ $# -ge 2 ] || die 'usage: query <db> "<SQL>" [--engine presto|hive] [--max-rows N] [--out file] [--wait 秒]'
    db="$1"; sql="$2"; shift 2
    engine=presto; max="${TD_MAX_ROWS:-200}"; out=""; wait_s=150
    while [ $# -gt 0 ]; do
      case "$1" in
        --engine) engine="$2"; shift 2 ;;
        --max-rows) max="$2"; shift 2 ;;
        --out) out="$2"; shift 2 ;;
        --wait) wait_s="$2"; shift 2 ;;
        *) die "不明なオプション: $1" ;;
      esac
    done
    case "$engine" in presto|trino) engine=presto ;; hive) ;; *) die "engine は presto か hive" ;; esac
    printf '%s' "$sql" > "$TMPD/sql"
    resp="$(call POST "$API" "/v3/job/issue/$engine/$db" --data-urlencode "query@$TMPD/sql")" || exit 1
    id="$(printf '%s' "$resp" | grep -oE '"job_id" *: *"?[0-9]+' | grep -oE '[0-9]+$')"
    [ -n "$id" ] || die "ジョブを発行できませんでした: $resp"
    echo "# job $id を発行（$engine / ${db}）" >&2
    elapsed=0; st=""
    while [ "$elapsed" -lt "$wait_s" ]; do
      sj="$(call GET "$API" "/v3/job/status/$id")" || exit 1
      st="$(printf '%s' "$sj" | grep -oE '"status" *: *"[a-z]+"' | head -1 | grep -oE '[a-z]+"$' | tr -d '"')"
      case "$st" in success|error|killed) break ;; esac
      sleep 3; elapsed=$((elapsed + 3))
    done
    case "$st" in
      success) show_result "$id" "$max" "$out" ;;
      error|killed)
        echo "# job $id: $st" >&2
        call GET "$API" "/v3/job/show/$id" | { [ "$HAS_PY" = 1 ] && python3 -c '
import json,sys; d=json.load(sys.stdin); dbg=d.get("debug") or {}
print((dbg.get("stderr") or dbg.get("cmdout") or "")[-2000:])' || cat; }
        exit 1 ;;
      *) echo "# job $id はまだ実行中（${st}）。後で: td-api.sh job-status $id / job-result $id" ;;
    esac
    ;;
  job-status) [ $# -ge 1 ] || die "usage: job-status <job_id>"
              call GET "$API" "/v3/job/status/$1"; echo ;;
  job-result)
    [ $# -ge 1 ] || die "usage: job-result <job_id> [--max-rows N] [--out file]"
    id="$1"; shift; max="${TD_MAX_ROWS:-200}"; out=""
    while [ $# -gt 0 ]; do
      case "$1" in --max-rows) max="$2"; shift 2 ;; --out) out="$2"; shift 2 ;; *) die "不明なオプション: $1" ;; esac
    done
    show_result "$id" "$max" "$out" ;;
  parent-segments) call GET "$CDP" /audiences | fmt segments ;;
  segments)   [ $# -ge 1 ] || die "usage: segments <parent_segment_id>"
              call GET "$CDP" "/audiences/$1/segments" | fmt segments ;;
  wf-projects)  call GET "$WF" /api/projects | fmt wf-projects ;;
  wf-workflows) [ $# -ge 1 ] || die "usage: wf-workflows <project_id>"
                call GET "$WF" "/api/projects/$1/workflows" | fmt wf-workflows ;;
  wf-attempts)  call GET "$WF" "/api/attempts?last=${1:-20}" | fmt wf-attempts ;;
  get)
    [ $# -ge 2 ] || die "usage: get <api|cdp|workflow> </path>"
    case "$1" in api) h="$API" ;; cdp) h="$CDP" ;; workflow) h="$WF" ;; *) die "api / cdp / workflow のいずれか" ;; esac
    case "$2" in /*) ;; *) die "path は / から始めてください" ;; esac
    call GET "$h" "$2" | fmt raw ;;
  help|-h|--help) sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//' ;;
  *) die "不明なコマンド: ${cmd}（help で一覧）" ;;
esac
