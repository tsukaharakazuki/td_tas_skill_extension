#!/usr/bin/env bash
# setup-tdx.sh — お客様の環境を診断し、合う導入プランで tdx を用意して検証する。
#
#   bash setup-tdx.sh plan                 環境を診断し、選べるプランと推奨を表示する（何も変更しない）
#   bash setup-tdx.sh install <A|B|C|D>    選んだプランで導入し、tdx_setup.conf に記録する
#   bash setup-tdx.sh verify               導入結果を検証する（版・通信・認証・権限範囲）
#   source setup-tdx.sh                    記録済みの設定で PATH と認証情報を読み込む
#
# プラン:
#   A  npm 直接       registry.npmjs.org から版固定で導入
#   B  社内ミラー     社内の npm ミラー（NPM_REGISTRY）から版固定で導入
#   C  オフライン一式 scripts/build-tdx-bundle.sh で作った一式を SHA-256 照合して展開（npm 通信なし）
#   D  curl のみ      tdx を入れず td-api.sh を使う（Node.js 不要・機能限定）
#
# 作業フォルダ（TD_WORKDIR。未指定ならスクリプトと同階層 → $HOME/mnt 配下の tdx_key.txt から探す）:
#   tdx_key.txt          1行目: APIキー / 2行目: リージョン（任意、既定 us01）
#   tdx_setup.conf       選んだプランの記録（install が書く。お客様の設定として残る）
#   tdx-bundle-*.tgz     プラン C の一式と .sha256
#   runtime/             tdx の導入先
#   td-api.sh            プラン D 用
#
# 環境変数（初回の plan / install で使う。install 後は tdx_setup.conf の値が既定になる）:
#   TDX_VERSION   導入する tdx の版（既定 2026.9.0）
#   NPM_REGISTRY  プラン B のミラー URL

# ---------- 共通 ----------
_SETUP_SOURCED=0
(return 0 2>/dev/null) && _SETUP_SOURCED=1

_say()  { printf '%s\n' "$*"; }
_ok()   { printf '[OK] %s\n' "$*"; }
_ng()   { printf '[NG] %s\n' "$*"; }
_na()   { printf '[--] %s\n' "$*"; }

_find_workdir() {
  local d
  d="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
  if [ -n "${TD_WORKDIR:-}" ]; then return 0; fi
  if [ -s "$d/tdx_key.txt" ]; then TD_WORKDIR="$d"; return 0; fi
  local f; f="$(find "$HOME/mnt" -maxdepth 4 -name 'tdx_key.txt' -size +0 2>/dev/null | head -1)"
  [ -n "$f" ] && TD_WORKDIR="$(dirname "$f")"
}

# tdx_setup.conf を「KEY=値」として読む（source しない）
_conf_get() {
  [ -f "$TD_WORKDIR/tdx_setup.conf" ] || return 0
  sed -n "s/^$1=//p" "$TD_WORKDIR/tdx_setup.conf" | tail -1 | tr -d '"'"'"
}

_load_settings() {
  CONF_MODE="$(_conf_get TDX_SETUP_MODE)"
  TDX_VERSION="${TDX_VERSION:-$(_conf_get TDX_VERSION)}"; TDX_VERSION="${TDX_VERSION:-2026.9.0}"
  NPM_REGISTRY="${NPM_REGISTRY:-$(_conf_get NPM_REGISTRY)}"
  TDX_SITE_FILE="$(sed -n '2p' "$TD_WORKDIR/tdx_key.txt" 2>/dev/null | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')"
  SITE="${TDX_SITE:-${TDX_SITE_FILE:-us01}}"
  case "$SITE" in
    ap01|jp01) H_API=api.treasuredata.co.jp    H_CDP=api-cdp.treasuredata.co.jp    H_WF=api-workflow.treasuredata.co.jp ;;
    eu01)      H_API=api.eu01.treasuredata.com H_CDP=api-cdp.eu01.treasuredata.com H_WF=api-workflow.eu01.treasuredata.com ;;
    ap02)      H_API=api.ap02.treasuredata.com H_CDP=api-cdp.ap02.treasuredata.com H_WF=api-workflow.ap02.treasuredata.com ;;
    *)         H_API=api.treasuredata.com      H_CDP=api-cdp.treasuredata.com      H_WF=api-workflow.treasuredata.com ;;
  esac
}

_sha256() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1"; else shasum -a 256 "$1"; fi | awk '{print $1}'; }
_http()   { curl -s -o /dev/null -w '%{http_code}' --max-time 15 "$1" 2>/dev/null; }
_latest_bundle() { ls -1 "$TD_WORKDIR"/tdx-bundle-*.tgz 2>/dev/null | sort -V | tail -1; }

_node_ok() {
  command -v node >/dev/null 2>&1 || return 1
  local v; v="$(node -v 2>/dev/null | tr -d v)"
  [ "$(printf '%s\n22.12.0\n' "$v" | sort -V | head -1)" = "22.12.0" ]
}

_npm_view() {  # $1 = registry URL（空なら既定）
  command -v npm >/dev/null 2>&1 || return 1
  local args=(view "@treasuredata/tdx@$TDX_VERSION" version)
  [ -n "${1:-}" ] && args+=(--registry "$1")
  local out; out="$(timeout 30 npm "${args[@]}" 2>/dev/null)" || return 1
  [ "$out" = "$TDX_VERSION" ]
}

_load_key() {
  export TDX_API_KEY="$(sed -n '1p' "$TD_WORKDIR/tdx_key.txt" | tr -d '[:space:]')"
  export TDX_SITE="$SITE"
}

# ---------- plan ----------
cmd_plan() {
  _say "== 環境の診断（作業フォルダ: $TD_WORKDIR / リージョン: $SITE / tdx $TDX_VERSION）"
  local td=0 node=0 pub=0 mir=0 bun=0 have=0 bundle=""

  if [ "$(_http "https://$H_API/v3/system/server_status")" = 200 ]; then td=1; _ok "Treasure Data に到達できる（$H_API）"
  else _ng "Treasure Data に到達できない（$H_API）→ ネットワーク許可に *.treasuredata.com / *.treasuredata.co.jp が必要"; fi

  if _node_ok; then node=1; _ok "Node.js $(node -v)（22.12 以上）"
  elif command -v node >/dev/null 2>&1; then _ng "Node.js $(node -v) は古い（22.12 以上が必要）"
  else _ng "Node.js が無い（プラン A/B/C には必要）"; fi

  if [ -x "$TD_WORKDIR/runtime/bin/tdx" ]; then have=1; _ok "導入済みの tdx: $("$TD_WORKDIR/runtime/bin/tdx" --version 2>/dev/null | head -1)"
  else _na "導入済みの tdx: なし"; fi

  if _npm_view ""; then pub=1; _ok "registry.npmjs.org から tdx $TDX_VERSION を取得できる"
  else _na "registry.npmjs.org: 到達できない、または npm が無い"; fi

  if [ -n "$NPM_REGISTRY" ]; then
    if _npm_view "$NPM_REGISTRY"; then mir=1; _ok "社内ミラー（$NPM_REGISTRY）から tdx $TDX_VERSION を取得できる"
    else _ng "社内ミラー（$NPM_REGISTRY）から tdx $TDX_VERSION を取得できない（URL・認証・版を確認）"; fi
  else _na "社内ミラー: 未指定（NPM_REGISTRY）"; fi

  bundle="$(_latest_bundle)"
  if [ -n "$bundle" ]; then
    if [ -s "$bundle.sha256" ] && [ "$(awk '{print $1}' "$bundle.sha256")" = "$(_sha256 "$bundle")" ]; then
      bun=1; _ok "オフライン一式: $(basename "$bundle")（SHA-256 一致）"
    else _ng "オフライン一式: $(basename "$bundle")（.sha256 が無いか不一致）"; fi
  else _na "オフライン一式: なし"; fi

  _say ""
  _say "== 選べるプラン"
  local A B C D why
  why=""; [ $node = 1 ] || why="Node.js 22.12 以上が必要"; [ $pub = 1 ] || why="${why:+$why / }registry.npmjs.org の許可が必要"
  [ -z "$why" ] && A=1 || A=0
  _say "  A npm 直接       $([ $A = 1 ] && echo '○ 利用可' || echo "× $why")"
  why=""; [ $node = 1 ] || why="Node.js 22.12 以上が必要"; [ $mir = 1 ] || why="${why:+$why / }NPM_REGISTRY に取得可能なミラーが必要"
  [ -z "$why" ] && B=1 || B=0
  _say "  B 社内ミラー     $([ $B = 1 ] && echo '○ 利用可' || echo "× $why")"
  why=""; [ $node = 1 ] || why="Node.js 22.12 以上が必要"; [ $bun = 1 ] || why="${why:+$why / }管理端末で作った一式を作業フォルダに置く必要"
  [ -z "$why" ] && C=1 || C=0
  _say "  C オフライン一式 $([ $C = 1 ] && echo '○ 利用可' || echo "× $why")"
  D=1; _say "  D curl のみ      ○ 利用可（tdx の全機能は使えない。参照・SQL・WF 参照中心）"
  [ $td = 1 ] || _say "  ※ どのプランも Treasure Data への到達が前提。先にネットワーク許可を設定する"

  local rec=D
  if   [ $have = 1 ] && [ -n "$CONF_MODE" ]; then rec="$CONF_MODE"
  elif [ $B = 1 ]; then rec=B
  elif [ $C = 1 ]; then rec=C
  elif [ $A = 1 ]; then rec=A
  fi
  _say ""
  _say "== 推奨: プラン $rec"
  [ -n "$CONF_MODE" ] && _say "   （記録済みの設定: プラン $CONF_MODE）"
  _say "RECOMMENDED=$rec"
  _say "AVAILABLE=$( [ $A = 1 ] && printf A)$( [ $B = 1 ] && printf B)$( [ $C = 1 ] && printf C)D"
}

# ---------- install ----------
_rollback() {
  _ng "$1"
  if [ -d "$TD_WORKDIR/runtime.old" ]; then
    rm -rf "$TD_WORKDIR/runtime"; mv "$TD_WORKDIR/runtime.old" "$TD_WORKDIR/runtime"
    _say "以前の runtime/ に戻しました"
  fi
  return 1
}
_write_conf() {
  {
    echo "# td-claude2tdx-connect の導入設定（setup-tdx.sh install が書き込む）"
    echo "TDX_SETUP_MODE=$1"
    echo "TDX_VERSION=$TDX_VERSION"
    echo "NPM_REGISTRY=${NPM_REGISTRY:-}"
    echo "INSTALLED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  } > "$TD_WORKDIR/tdx_setup.conf"
}

cmd_install() {
  local mode; mode="$(printf '%s' "${1:-}" | tr '[:lower:]' '[:upper:]')"
  case "$mode" in A|B|C|D) ;; *) _say "usage: setup-tdx.sh install <A|B|C|D>（まず plan で確認）"; return 1 ;; esac

  if [ "$mode" != D ]; then
    _node_ok || { _ng "Node.js 22.12 以上が必要です"; return 1; }
    if [ -d "$TD_WORKDIR/runtime" ]; then
      _say "既存の runtime/ を runtime.old/ に退避します"
      rm -rf "$TD_WORKDIR/runtime.old"; mv "$TD_WORKDIR/runtime" "$TD_WORKDIR/runtime.old"
    fi
  fi

  case "$mode" in
    A|B)
      local reg=()
      if [ "$mode" = B ]; then
        [ -n "$NPM_REGISTRY" ] || { _rollback "プラン B には NPM_REGISTRY が必要です"; return 1; }
        reg=(--registry "$NPM_REGISTRY")
      fi
      _say "tdx $TDX_VERSION を導入しています（$([ "$mode" = B ] && echo "$NPM_REGISTRY" || echo registry.npmjs.org)、60秒ほど）"
      npm i -g --prefix "$TD_WORKDIR/runtime" ${reg[@]+"${reg[@]}"} --ignore-scripts --omit=optional \
        --no-fund --no-audit "@treasuredata/tdx@$TDX_VERSION" >/dev/null 2>&1 \
        || { _rollback "導入に失敗しました"; return 1; }
      ;;
    C)
      local b; b="$(_latest_bundle)"
      [ -n "$b" ] && [ -s "$b.sha256" ] || { _rollback "tdx-bundle-*.tgz と .sha256 が作業フォルダにありません"; return 1; }
      [ "$(awk '{print $1}' "$b.sha256")" = "$(_sha256 "$b")" ] \
        || { _rollback "SHA-256 が一致しません。一式が改変・破損している可能性があるため展開しません"; return 1; }
      TDX_VERSION="$(basename "$b" .tgz | sed 's/^tdx-bundle-//')"
      mkdir -p "$TD_WORKDIR/runtime" && tar xzf "$b" -C "$TD_WORKDIR/runtime" \
        || { _rollback "展開に失敗しました"; return 1; }
      _ok "$(basename "$b") を照合して展開しました"
      ;;
    D)
      [ -f "$TD_WORKDIR/td-api.sh" ] || { _ng "td-api.sh を作業フォルダに置いてください"; return 1; }
      chmod +x "$TD_WORKDIR/td-api.sh"
      ;;
  esac
  rm -rf "$TD_WORKDIR/runtime.old"
  _write_conf "$mode"
  _ok "プラン $mode で導入し、tdx_setup.conf に記録しました"
  _say "続けて検証: bash setup-tdx.sh verify"
}

# ---------- verify ----------
cmd_verify() {
  local fail=0 mode="${CONF_MODE:-}"
  _say "== 検証（プラン ${mode:-未設定} / リージョン $SITE）"
  [ -n "$mode" ] || { _ng "tdx_setup.conf がありません。先に install を実行してください"; return 1; }

  # 1. 通信
  local h c
  for h in "$H_API" "$H_CDP" "$H_WF"; do
    c="$(_http "https://$h/")"
    if [ "$c" != 000 ]; then _ok "到達: $h"; else _ng "到達できない: $h"; fail=1; fi
  done

  # 2. 本体と版
  _load_key
  if [ "$mode" = D ]; then
    if [ -x "$TD_WORKDIR/td-api.sh" ]; then _ok "td-api.sh あり"; else _ng "td-api.sh が無い"; fail=1; fi
    local out; out="$(TD_WORKDIR="$TD_WORKDIR" "$TD_WORKDIR/td-api.sh" status 2>&1)"
    if printf '%s' "$out" | grep -q 'auth: OK'; then _ok "$(printf '%s' "$out" | grep 'auth: OK')"
    else _ng "認証: $(printf '%s' "$out" | tail -1)"; fail=1; fi
  else
    export PATH="$TD_WORKDIR/runtime/bin:$PATH"
    local v; v="$(tdx --version 2>/dev/null | head -1)"
    if printf '%s' "$v" | grep -q "tdx $TDX_VERSION"; then _ok "版: $v"
    else _ng "版: '${v:-不明}'（期待: $TDX_VERSION）"; fail=1; fi

    # 3. 認証
    if tdx --site "$SITE" auth status >/dev/null 2>&1; then _ok "認証: 成功"
    else _ng "認証: 失敗（キー / リージョンを確認。tdx --site $SITE auth status で詳細）"; fail=1; fi

    # 4. 権限範囲（参照のみで確認）
    local n
    n="$(tdx --site "$SITE" databases --json 2>/dev/null | grep -o '"name"' | wc -l | tr -d ' ')"
    if [ "${n:-0}" -gt 0 ]; then _ok "見えるデータベース: $n 件（多すぎる場合はポリシーで絞る）"
    else _ng "データベースが1件も見えない（権限かリージョンを確認）"; fail=1; fi
    if tdx --site "$SITE" wf projects >/dev/null 2>&1; then _ok "ワークフロー API: 参照可"
    else _ng "ワークフロー API: 参照できない"; fail=1; fi
  fi

  _say ""
  if [ $fail = 0 ]; then _say "検証結果: 合格"; _say "VERIFY=PASS"; return 0
  else _say "検証結果: 不合格（[NG] の項目を確認）"; _say "VERIFY=FAIL"; return 1; fi
}

# ---------- main ----------
_find_workdir
if [ -z "${TD_WORKDIR:-}" ] || [ ! -s "$TD_WORKDIR/tdx_key.txt" ]; then
  _say "APIキーが見つかりません。作業フォルダ（既定: TreasureAI）に tdx_key.txt を作り、1行目にキーを書いてください。"
  _say "場所を明示する場合: TD_WORKDIR=<パス> bash setup-tdx.sh plan"
  if [ $_SETUP_SOURCED = 1 ]; then return 1; else exit 1; fi
fi
_load_settings

if [ $_SETUP_SOURCED = 1 ]; then
  # source された場合: 記録済み設定で環境を読み込むだけ（導入はしない）
  export PATH="$TD_WORKDIR/runtime/bin:$PATH"
  _load_key
  _say "workdir: $TD_WORKDIR / plan: ${CONF_MODE:-未設定} / site: $SITE"
  command -v tdx >/dev/null 2>&1 && tdx --version 2>/dev/null | head -1
  return 0
fi

case "${1:-plan}" in
  plan)    cmd_plan ;;
  install) shift; cmd_install "$@" ;;
  verify)  cmd_verify ;;
  *) sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'; exit 1 ;;
esac
