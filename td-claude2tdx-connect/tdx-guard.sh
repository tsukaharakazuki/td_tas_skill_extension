#!/usr/bin/env bash
# tdx-guard.sh — tdx の前段で、お客様が決めた操作範囲（tdx_policy.conf）を強制する。
#
# setup-tdx.sh install が runtime/bin/tdx をこのガード経由に差し替える。
# Claude もユーザーも、ふだんどおり `tdx ...` と打てばガードを通る。
#
#   tdx-guard.sh <tdx の引数...>           判定して、許可なら本物の tdx を実行
#   tdx-guard.sh --check <tdx の引数...>   判定結果だけ表示（実行しない）
#
# tdx_policy.conf（作業フォルダ）:
#   data=none|read|write       DB・テーブル参照、SQL、ジョブ
#   workflow=none|read|write   ワークフロー（push / run / 削除 / スケジュール / シークレット）
#   cdp=none|read|write        親セグメント・セグメント・アクティベーション・コネクション・CAS
#   journey=none|read|write    ジャーニー
#   engage=none|read|write     Engage・配信
#   ai=none|read|write         LLM エージェント・チャット
#   admin=none|read            ユーザー・ポリシー
#
# 判定:
#   - 操作を「カテゴリ」と「read / write」に分類し、ポリシーの水準と比べる
#   - write は、ポリシーで許可されていても TD_ALLOW_WRITE=1 が無ければ止める（都度の了承を必須にする）
#     ただし --dry-run 付き（プレビュー）は了承なしで通す。ポリシーの水準は満たす必要がある
#   - SQL（query / job submit）は文面を見て read / write を判定する。判定できない形は write 扱い
#   - 分類できないコマンドは拒否する。ポリシーファイルが無い場合も拒否する（安全側に倒す）
#   - 判定結果はすべて tdx_audit.log に残す
#
# 注意: これは Claude とユーザーの誤操作を防ぐための仕組みで、セキュリティ境界ではない。
#       最終的な権限境界は API キーのユーザーに割り当てた Treasure Data のポリシー。

set -uo pipefail

GUARD_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
WORKDIR="${TD_WORKDIR:-$GUARD_DIR}"
POLICY="$WORKDIR/tdx_policy.conf"
AUDIT="$WORKDIR/tdx_audit.log"

CHECK_ONLY=0
[ "${1:-}" = "--check" ] && { CHECK_ONLY=1; shift; }
ARGS=(); [ $# -gt 0 ] && ARGS=("$@")

# ---------- 本物の tdx ----------
real_tdx() {
  local e
  for e in "$WORKDIR/runtime/lib/node_modules/@treasuredata/tdx/dist/bin.js" \
           "$WORKDIR/runtime/node_modules/@treasuredata/tdx/dist/bin.js"; do
    [ -f "$e" ] && { exec node "$e" "$@"; }
  done
  echo "tdx 本体が見つかりません（$WORKDIR/runtime）" >&2; exit 127
}

# ---------- ポリシー ----------
pol() {
  local v=""
  [ -f "$POLICY" ] && v="$(sed -n "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*\([a-z]*\).*/\1/p" "$POLICY" | tail -1)"
  case "$v" in read|write) echo "$v" ;; *) echo none ;; esac
}
rank() { case "$1" in write) echo 2 ;; read) echo 1 ;; *) echo 0 ;; esac; }

# ---------- 引数の整理 ----------
# 値を取るグローバルオプションの値を位置引数と取り違えないように除く
POS=(); HAS_RESULT=0; DRY_RUN=0; SQL_FILE=""
i=0
while [ $i -lt ${#ARGS[@]} ]; do
  a="${ARGS[$i]}"
  case "$a" in
    -C|--directory|-p|--profile|--site|--format|--output|--limit|--timeout|--session|--parent-segment|--llm-project|\
    -d|--database|--in|--catalog|--job-type|--revision|--reason|--resume-from|--params)
      i=$((i+2)); continue ;;
    -f|--file) SQL_FILE="${ARGS[$((i+1))]:-}"; i=$((i+2)); continue ;;
    --file=*) SQL_FILE="${a#--file=}" ;;
    --result|--result=*) HAS_RESULT=1; [ "$a" = --result ] && i=$((i+1)) ;;
    --dry-run) DRY_RUN=1 ;;
    -*) ;;
    *) POS+=("$a") ;;
  esac
  i=$((i+1))
done

READ_VERBS=" list show view desc describe sql fields stats traffic columns activations versions version validate preview pull download result schema types settings history models timeline projects workflows sessions attempts schedules campaigns always-on-campaigns templates workspaces senders deleted configuration_versions agents status tasks logs log "
NEST_GROUPS=" campaign always-on-campaign template domain landing-page workspace line-sender-account line-imagemap-image media project session schedule secrets rt pz p13n jn sg "

in_list() { case "$2" in *" $1 "*) return 0 ;; esac; return 1; }

# 位置引数 POS[1..] から動詞を探して read / write を返す
verb_level() {
  local k=1 t
  while [ $k -lt ${#POS[@]} ]; do
    t="${POS[$k]}"
    if in_list "$t" "$NEST_GROUPS"; then k=$((k+1)); continue; fi
    if [ "$t" = use ]; then echo local; return; fi
    if in_list "$t" "$READ_VERBS"; then echo read; return; fi
    echo write; return   # 既知の読み取り動詞以外は書き込み扱い
  done
  echo read             # 動詞なし（tdx journeys / tdx engage campaigns など）は一覧表示
}

# SQL が参照系か（コメントを除き、先頭キーワードと危険語で判定）
sql_level() {
  local s="$1"
  [ -n "$s" ] || { echo write; return; }
  s="$(printf '%s' "$s" | sed -e 's/--.*$//' | tr '\n' ' ' | sed -E 's#/\*([^*]|\*+[^*/])*\*+/# #g' | tr '[:lower:]' '[:upper:]')"
  if printf '%s' "$s" | grep -Eq '^[[:space:](]*(SELECT|WITH|SHOW|DESCRIBE|DESC|EXPLAIN|VALUES)[[:space:]]' \
     && ! printf '%s' "$s" | grep -Eqw 'INSERT|DELETE|DROP|CREATE|ALTER|UPDATE|MERGE|TRUNCATE|GRANT|REVOKE|CALL|OVERWRITE'; then
    echo read
  else
    echo write
  fi
}

sql_text() {  # query / job submit の SQL 文面
  if [ -n "$SQL_FILE" ]; then cat "$SQL_FILE" 2>/dev/null; return; fi
  local k="$1"; printf '%s' "${POS[$k]:-}"
}

# ---------- 分類 ----------
CAT=""; LVL=""; WHY=""
top="${POS[0]:-}"
case "$top" in
  ""|status|unset|use|help) CAT=always; LVL=read ;;
  auth)        if [ "${POS[1]:-}" = status ]; then CAT=always; LVL=read; else CAT=blocked; WHY="キーファイル方式の認証を壊すため"; fi ;;
  profile|profiles) CAT=blocked; WHY="キーファイル方式の認証を壊すため" ;;
  mcp|claude|codex|chats|work) CAT=blocked; WHY="対話・常駐プロセスで返らなくなるため" ;;
  upgrade)     CAT=blocked; WHY="tdx_setup.conf の版とずれるため（setup-tdx.sh install で入れ直す）" ;;

  database|db|databases|table|tables|show|describe|desc) CAT=data; LVL="$(verb_level)"
               case "$top" in show|describe|desc) LVL=read ;; esac ;;
  query)       CAT=data; LVL="$(sql_level "$(sql_text 1)")" ;;
  job|jobs)    CAT=data
               if [ "${POS[1]:-}" = submit ]; then LVL="$(sql_level "$(sql_text 2)")"; else LVL="$(verb_level)"; fi
               [ $HAS_RESULT = 1 ] && { LVL=write; WHY="--result で外部へ出力するため"; } ;;

  workflow|wf) CAT=workflow
               if [ "${POS[1]:-}" = attempt ] && [[ "${POS[2]:-}" =~ ^[0-9]+$ ]]; then
                 case "${POS[3]:-}" in ""|tasks|logs|log|show) LVL=read ;; *) LVL=write ;; esac
               else LVL="$(verb_level)"; fi ;;

  segment|sg|segments|parent-segment|ps|parent-segments|activations|connection|connections|cas)
               CAT=cdp; LVL="$(verb_level)"; [ "$top" = activations ] && LVL=read ;;
  journey|journeys) CAT=journey; LVL="$(verb_level)" ;;
  engage|delivery)  CAT=engage;  LVL="$(verb_level)" ;;
  agent|agents|chat|llm) CAT=ai; LVL="$(verb_level)"; [ "$top" = chat ] && LVL=write ;;
  user|users|policy) CAT=admin; LVL="$(verb_level)" ;;
  *) CAT=unknown; WHY="分類できないコマンドのため" ;;
esac
# 複数形の別名（tdx tables <pattern> など）は一覧表示
case "$top" in databases|tables|jobs|segments|parent-segments|journeys|agents|users|connections) LVL=read ;; esac
[ "$LVL" = local ] && { CAT=always; LVL=read; }

# ---------- 判定 ----------
DECISION=allow; REASON=""
if [ ! -f "$POLICY" ] && [ "$CAT" != always ]; then
  DECISION=deny; REASON="tdx_policy.conf がありません。setup-tdx.sh policy で操作範囲を設定してください"
elif [ "$CAT" = blocked ] || [ "$CAT" = unknown ]; then
  DECISION=deny; REASON="$WHY"
elif [ "$CAT" != always ]; then
  allowed="$(pol "$CAT")"
  if [ "$(rank "$allowed")" -lt "$(rank "$LVL")" ]; then
    DECISION=deny; REASON="操作範囲外: $CAT は '$allowed' まで（この操作は ${LVL}）"
  elif [ "$LVL" = write ] && [ "${TD_ALLOW_WRITE:-0}" != 1 ] && [ $DRY_RUN = 0 ]; then
    DECISION=deny; REASON="書き込み操作です。ユーザーの了承を得てから TD_ALLOW_WRITE=1 を付けて再実行してください${WHY:+（${WHY}）}"
  fi
fi

# ---------- 監査ログ ----------
log_cmd() {
  local out="" a mask=0
  for a in ${ARGS[@]+"${ARGS[@]}"}; do
    if [ $mask = 1 ]; then out+=" ***"; continue; fi
    out+=" ${a//$'\n'/ }"
    [ "$a" = set ] && in_list secrets " ${ARGS[*]} " && mask=1   # wf secrets set の値は残さない
  done
  printf '%s' "${out:1}" | cut -c1-500
}
if [ $CHECK_ONLY = 0 ] && ! { [ "$CAT" = always ] && [ "$DECISION" = allow ]; }; then
  { printf '%s\t%s\t%s/%s\t%s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$DECISION" "$CAT" "${LVL:--}" "$(log_cmd)"; } >> "$AUDIT" 2>/dev/null
fi

if [ $CHECK_ONLY = 1 ]; then
  printf '%s\t%s/%s\t%s\n' "$DECISION" "$CAT" "${LVL:--}" "${REASON:-}"
  [ "$DECISION" = allow ]; exit $?
fi

if [ "$DECISION" = deny ]; then
  echo "tdx-guard: 実行しませんでした — $REASON" >&2
  exit 126
fi
real_tdx ${ARGS[@]+"${ARGS[@]}"}
