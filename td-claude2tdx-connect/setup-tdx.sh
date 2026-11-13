#!/usr/bin/env bash
# setup-tdx.sh — お客様の環境を診断し、合う導入プランで tdx を用意して検証する。
#
#   bash setup-tdx.sh plan                 環境を診断し、選べるプランと推奨を表示する（何も変更しない）
#   bash setup-tdx.sh install <A|B|C|D>    選んだプランで導入し、tdx_setup.conf に記録する
#   bash setup-tdx.sh policy presets       操作範囲のプリセット一覧
#   bash setup-tdx.sh policy set <プリセット> [カテゴリ=水準 ...]
#                                          操作範囲を tdx_policy.conf に書く（例: policy set analyst workflow=read）
#   bash setup-tdx.sh policy show          現在の操作範囲と、TD 側で合わせるべき設定を表示
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
#   tdx_policy.conf      操作範囲の記録（policy set が書く）。tdx-guard.sh がこれを強制する
#   tdx-guard.sh         操作範囲のガード。install が runtime/bin/tdx をこのガード経由にする
#   tdx_audit.log        ガードの判定ログ
#   tdx-bundle-*.tgz     プラン C の一式と .sha256
#   runtime/             tdx の導入先
#   td-api.sh            プラン D 用
#
# 環境変数（初回の plan / install で使う。install 後は tdx_setup.conf の値が既定になる）:
#   TDX_VERSION        導入する tdx の版（既定 2026.10.10）
#   NPM_REGISTRY       プラン B のミラー URL
#   NPM_MIN_AGE_DAYS   公開から N 日未満の依存パッケージを選ばない（既定 7。0 で無効。プラン A/B）
#
# セキュリティ上の前提（2026-11 更新）:
#   - Node.js は 2026-10 のセキュリティリリース以降の版だけを使う（NODE_MIN_PATCHED）。
#     Brotli 復号の境界外書き込み（CVE-2026-111497）、TLS ホスト名検証の不備（CVE-2026-105483 / 106069 / 106072）、
#     eMudhra の中間 CA 侵害に対する CA 証明書の更新を含む
#   - NODE_TLS_REJECT_UNAUTHORIZED=0 など TLS 検証を無効にする設定があれば導入・実行しない
#   - Treasure Data への接続で、証明書チェーンに emSign / eMudhra が含まれていれば中止する（なりすましの疑い）

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
  TDX_VERSION="${TDX_VERSION:-$(_conf_get TDX_VERSION)}"; TDX_VERSION="${TDX_VERSION:-2026.10.10}"
  NPM_REGISTRY="${NPM_REGISTRY:-$(_conf_get NPM_REGISTRY)}"
  NPM_MIN_AGE_DAYS="${NPM_MIN_AGE_DAYS:-$(_conf_get NPM_MIN_AGE_DAYS)}"; NPM_MIN_AGE_DAYS="${NPM_MIN_AGE_DAYS:-7}"
  case "$NPM_MIN_AGE_DAYS" in ''|*[!0-9]*) NPM_MIN_AGE_DAYS=7 ;; esac
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
_http()   { curl -q -s -o /dev/null -w '%{http_code}' --max-time 15 "$1" 2>/dev/null; }
_latest_bundle() { ls -1 "$TD_WORKDIR"/tdx-bundle-*.tgz 2>/dev/null | sort -V | tail -1; }

# 系列ごとの「2026-10 セキュリティリリース」以降の版。表に無い系列は、これより古ければ EOL として拒否する
NODE_MIN_PATCHED="22.23.4 24.22.1 26.12.1"
NODE_REQ_TEXT="Node.js 22.23.4 / 24.22.1 / 26.12.1 以上（2026-10 のセキュリティ修正版）"

_ver_ge() { [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -1)" = "$2" ]; }

# Node.js が使えるか。使えなければ NODE_WHY に理由を入れて 1 を返す
_node_ok() {
  NODE_WHY=""
  command -v node >/dev/null 2>&1 || { NODE_WHY="Node.js が無い"; return 1; }
  local v major m newest=""
  v="$(node -v 2>/dev/null | tr -d v)"; major="${v%%.*}"
  case "$major" in ''|*[!0-9]*) NODE_WHY="Node.js の版を判定できない（${v:-不明}）"; return 1 ;; esac
  # zsh から source されても動くよう、単語分割に頼らず1行ずつ読む
  while read -r m; do
    [ -n "$m" ] || continue
    newest="${m%%.*}"
    if [ "${m%%.*}" = "$major" ]; then
      _ver_ge "$v" "$m" && return 0
      NODE_WHY="Node.js v$v は脆弱性修正前（v$m 以上が必要。CVE-2026-111497 ほか）"; return 1
    fi
  done <<EOF
$(printf '%s\n' "$NODE_MIN_PATCHED" | tr ' ' '\n')
EOF
  [ "$major" -gt "$newest" ] && return 0
  if _ver_ge "$v" 22.12.0; then NODE_WHY="Node.js v$v はサポート終了（EOL）の系列でセキュリティ修正が出ない"
  else NODE_WHY="Node.js v$v は古い"; fi
  return 1
}

# TLS 検証を無効にする設定が無いか（API キーを送るため、無効なら何もしない）
_tls_env_ok() {
  if [ "${NODE_TLS_REJECT_UNAUTHORIZED:-}" = 0 ]; then
    _ng "NODE_TLS_REJECT_UNAUTHORIZED=0 で TLS 検証が無効になっている（解除するまで tdx を使わない）"; return 1
  fi
  [ -n "${NODE_EXTRA_CA_CERTS:-}" ] && _na "NODE_EXTRA_CA_CERTS=${NODE_EXTRA_CA_CERTS} が追加の CA として信頼される（社内プロキシ用か確認）"
  return 0
}

# Treasure Data の証明書チェーンに emSign / eMudhra が含まれないか（2026-10 の中間 CA 侵害）
# 戻り値: 0 = 問題なし / 1 = 含まれる / 2 = 確認できない
_cert_chain_check() {
  local h="$1" chain=""
  chain="$(curl -q -s -o /dev/null --max-time 15 -w '%{certs}' "https://$h/" 2>/dev/null | grep -E '^(Subject|Issuer):')"
  if [ -z "$chain" ] && command -v openssl >/dev/null 2>&1; then
    chain="$(_with_timeout 20 openssl s_client -connect "$h:443" -servername "$h" -showcerts </dev/null 2>/dev/null | grep -E '^ *([0-9]+ s:|i:)')"
  fi
  [ -n "$chain" ] || return 2
  printf '%s' "$chain" | grep -qiE 'emsign|emudhra' && return 1
  return 0
}

_report_cert_chain() {  # $1 = host。含まれていれば 1 を返す
  _cert_chain_check "$1"
  case $? in
    0) _ok "証明書チェーン: $1 に emSign / eMudhra を含まない" ;;
    1) _ng "証明書チェーン: $1 の経路に emSign / eMudhra の証明書がある（なりすましの疑い。接続を中止してネットワーク管理者に確認）"; return 1 ;;
    *) _na "証明書チェーン: $1 は確認できなかった（curl 7.88 以上か openssl があれば確認する）" ;;
  esac
  return 0
}

# プラン A/B: 公開から NPM_MIN_AGE_DAYS 日未満の版を依存解決に使わない（乗っ取られたパッケージの新版を避ける）
_npm_cooldown_args() {
  [ "${NPM_MIN_AGE_DAYS:-0}" -gt 0 ] 2>/dev/null || return 0
  local d; d="$(node -e 'console.log(new Date(Date.now()-Number(process.argv[1])*864e5).toISOString())' "$NPM_MIN_AGE_DAYS" 2>/dev/null)"
  [ -n "$d" ] && printf '%s\n' "--before=$d"
}

# macOS には timeout が無いので、あるものを使う（無ければそのまま実行）
_with_timeout() {
  local t="$1"; shift
  if command -v timeout >/dev/null 2>&1; then timeout "$t" "$@"
  elif command -v gtimeout >/dev/null 2>&1; then gtimeout "$t" "$@"
  else "$@"; fi
}

_npm_view() {  # $1 = registry URL（空なら既定）
  command -v npm >/dev/null 2>&1 || return 1
  local args=(view "@treasuredata/tdx@$TDX_VERSION" version)
  [ -n "${1:-}" ] && args+=(--registry "$1")
  local out; out="$(_with_timeout 30 npm "${args[@]}" 2>/dev/null)" || return 1
  [ "$out" = "$TDX_VERSION" ]
}

_load_key() {
  export TDX_API_KEY="$(sed -n '1p' "$TD_WORKDIR/tdx_key.txt" | tr -d '[:space:]')"
  export TDX_SITE="$SITE"
}

# ---------- plan ----------
cmd_plan() {
  _say "== 環境の診断（作業フォルダ: $TD_WORKDIR / リージョン: $SITE / tdx ${TDX_VERSION}）"
  local td=0 node=0 pub=0 mir=0 bun=0 have=0 tls=1 bundle=""

  if [ "$(_http "https://$H_API/v3/system/server_status")" = 200 ]; then td=1; _ok "Treasure Data に到達できる（${H_API}）"
  else _ng "Treasure Data に到達できない（${H_API}）→ ネットワーク許可に *.treasuredata.com / *.treasuredata.co.jp が必要"; fi
  if [ $td = 1 ]; then _report_cert_chain "$H_API" || td=0; fi
  _tls_env_ok || tls=0

  if _node_ok; then node=1; _ok "Node.js $(node -v)（セキュリティ修正版）"
  else _ng "${NODE_WHY} → プラン A/B/C には ${NODE_REQ_TEXT} が必要"; fi
  [ $tls = 1 ] || node=0

  if [ -x "$TD_WORKDIR/runtime/bin/tdx" ]; then have=1; _ok "導入済みの tdx: $("$TD_WORKDIR/runtime/bin/tdx" --version 2>/dev/null | head -1)"
  else _na "導入済みの tdx: なし"; fi

  if _npm_view ""; then pub=1; _ok "registry.npmjs.org から tdx $TDX_VERSION を取得できる"
  else _na "registry.npmjs.org: 到達できない、または npm が無い"; fi

  if [ -n "$NPM_REGISTRY" ]; then
    if _npm_view "$NPM_REGISTRY"; then mir=1; _ok "社内ミラー（${NPM_REGISTRY}）から tdx $TDX_VERSION を取得できる"
    else _ng "社内ミラー（${NPM_REGISTRY}）から tdx $TDX_VERSION を取得できない（URL・認証・版を確認）"; fi
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
  local nwhy="${NODE_REQ_TEXT} が必要"; [ $tls = 1 ] || nwhy="TLS 検証の無効化を解除する必要"
  why=""; [ $node = 1 ] || why="$nwhy"; [ $pub = 1 ] || why="${why:+$why / }registry.npmjs.org の許可が必要"
  [ -z "$why" ] && A=1 || A=0
  _say "  A npm 直接       $([ $A = 1 ] && echo '○ 利用可' || echo "× $why")"
  why=""; [ $node = 1 ] || why="$nwhy"; [ $mir = 1 ] || why="${why:+$why / }NPM_REGISTRY に取得可能なミラーが必要"
  [ -z "$why" ] && B=1 || B=0
  _say "  B 社内ミラー     $([ $B = 1 ] && echo '○ 利用可' || echo "× $why")"
  why=""; [ $node = 1 ] || why="$nwhy"; [ $bun = 1 ] || why="${why:+$why / }管理端末で作った一式を作業フォルダに置く必要"
  [ -z "$why" ] && C=1 || C=0
  _say "  C オフライン一式 $([ $C = 1 ] && echo '○ 利用可' || echo "× $why")"
  D=1; _say "  D curl のみ      ○ 利用可（tdx の全機能は使えない。参照・SQL・WF 参照中心）"
  [ "${NPM_MIN_AGE_DAYS}" -gt 0 ] && { [ $A = 1 ] || [ $B = 1 ]; } \
    && _say "  ※ A/B は公開から ${NPM_MIN_AGE_DAYS} 日未満の依存パッケージを使わない（NPM_MIN_AGE_DAYS）"
  [ $td = 1 ] || _say "  ※ どのプランも Treasure Data への到達が前提。先にネットワーク許可を設定する"

  local rec=D
  if   [ $have = 1 ] && [ -n "$CONF_MODE" ]; then rec="$CONF_MODE"
  elif [ $B = 1 ]; then rec=B
  elif [ $C = 1 ]; then rec=C
  elif [ $A = 1 ]; then rec=A
  fi
  _say ""
  _say "== 推奨: プラン $rec"
  [ -n "$CONF_MODE" ] && _say "   （記録済みの設定: プラン ${CONF_MODE}）"
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
    echo "NPM_MIN_AGE_DAYS=${NPM_MIN_AGE_DAYS}"
    echo "NODE_VERSION=$(node -v 2>/dev/null)"
    echo "INSTALLED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  } > "$TD_WORKDIR/tdx_setup.conf"
}

cmd_install() {
  local mode; mode="$(printf '%s' "${1:-}" | tr '[:lower:]' '[:upper:]')"
  case "$mode" in A|B|C|D) ;; *) _say "usage: setup-tdx.sh install <A|B|C|D>（まず plan で確認）"; return 1 ;; esac

  _tls_env_ok || return 1
  _report_cert_chain "$H_API" >/dev/null || { _ng "Treasure Data の証明書チェーンに emSign / eMudhra が含まれるため導入しません"; return 1; }
  if [ "$mode" != D ]; then
    _node_ok || { _ng "${NODE_WHY}。${NODE_REQ_TEXT} が必要です"; return 1; }
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
      local cool; cool="$(_npm_cooldown_args)"
      [ -n "$cool" ] && reg+=("$cool")
      _say "tdx $TDX_VERSION を導入しています（$([ "$mode" = B ] && echo "$NPM_REGISTRY" || echo registry.npmjs.org)、60秒ほど）"
      [ -n "$cool" ] && _say "公開から ${NPM_MIN_AGE_DAYS} 日未満の依存パッケージは使いません（${cool#--before=} より前の版で解決）"
      npm i -g --prefix "$TD_WORKDIR/runtime" ${reg[@]+"${reg[@]}"} --ignore-scripts --omit=optional \
        --no-fund --no-audit "@treasuredata/tdx@$TDX_VERSION" >/dev/null 2>&1 \
        || { _rollback "導入に失敗しました（tdx $TDX_VERSION が公開から ${NPM_MIN_AGE_DAYS} 日未満なら、古い版を TDX_VERSION で指定する）"; return 1; }
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
  if [ "$mode" != D ]; then
    _install_guard || { _rollback "ガードの組み込みに失敗しました"; return 1; }
  fi
  rm -rf "$TD_WORKDIR/runtime.old"
  _write_conf "$mode"
  _ok "プラン $mode で導入し、tdx_setup.conf に記録しました"
  [ -f "$TD_WORKDIR/tdx_policy.conf" ] || _say "操作範囲が未設定です。tdx は status 以外すべて拒否されます: bash setup-tdx.sh policy set <プリセット>"
  _say "続けて検証: bash setup-tdx.sh verify"
}

# runtime/bin/tdx を tdx-guard.sh 経由に差し替える
_install_guard() {
  [ -f "$TD_WORKDIR/tdx-guard.sh" ] || { _ng "tdx-guard.sh を作業フォルダに置いてください"; return 1; }
  chmod +x "$TD_WORKDIR/tdx-guard.sh"
  mkdir -p "$TD_WORKDIR/runtime/bin"
  rm -f "$TD_WORKDIR/runtime/bin/tdx"
  cat > "$TD_WORKDIR/runtime/bin/tdx" <<'SHIM'
#!/usr/bin/env bash
# tdx-guard 経由で tdx を実行する（setup-tdx.sh install が生成）
D="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TD_WORKDIR="$D" exec bash "$D/tdx-guard.sh" "$@"
SHIM
  chmod +x "$TD_WORKDIR/runtime/bin/tdx"
  _ok "tdx を操作範囲ガード（tdx-guard.sh）経由にしました"
}

# ---------- policy ----------
POLICY_CATS="data workflow cdp journey engage ai admin"
_cat_label() {
  case "$1" in
    data) echo "データ・SQL（DB/テーブル参照、クエリ、ジョブ）" ;;
    workflow) echo "ワークフロー（push / run / スケジュール / シークレット）" ;;
    cdp) echo "CDP（親セグメント、セグメント、アクティベーション、CAS）" ;;
    journey) echo "ジャーニー" ;;
    engage) echo "Engage・配信（キャンペーン、テンプレート、送信）" ;;
    ai) echo "AI（LLM エージェント、チャット）" ;;
    admin) echo "管理（ユーザー、ポリシー）" ;;
  esac
}
_lvl_label() { case "$1" in write) echo "参照・更新" ;; read) echo "参照のみ" ;; *) echo "不可" ;; esac; }

_preset() {  # 出力: "data=.. workflow=.. ..."
  case "$1" in
    readonly)  echo "data=read  workflow=read  cdp=read  journey=read  engage=read  ai=none  admin=none" ;;
    analyst)   echo "data=write workflow=read  cdp=read  journey=read  engage=read  ai=none  admin=none" ;;
    wf-ops)    echo "data=write workflow=write cdp=read  journey=read  engage=read  ai=none  admin=none" ;;
    marketing) echo "data=read  workflow=read  cdp=write journey=write engage=write ai=none  admin=none" ;;
    full)      echo "data=write workflow=write cdp=write journey=write engage=write ai=write admin=read" ;;
    none)      echo "data=none  workflow=none  cdp=none  journey=none  engage=none  ai=none  admin=none" ;;
    *) return 1 ;;
  esac
}

cmd_policy_presets() {
  _say "| プリセット | 用途 | データ・SQL | ワークフロー | CDP | ジャーニー | Engage | AI | 管理 |"
  _say "|---|---|---|---|---|---|---|---|---|"
  local p desc kv line
  for p in readonly analyst wf-ops marketing full; do
    case "$p" in
      readonly)  desc="参照のみ（SQL は SELECT 系だけ）" ;;
      analyst)   desc="分析（書き込み SQL 可、WF は参照のみ）" ;;
      wf-ops)    desc="分析＋ワークフロー運用" ;;
      marketing) desc="施策運用（セグメント・ジャーニー・Engage を更新）" ;;
      full)      desc="ほぼ全権（管理は参照のみ）" ;;
    esac
    line="| $p | $desc |"
    for kv in $(_preset "$p"); do line+=" $(_lvl_label "${kv#*=}") |"; done
    _say "$line"
  done
  _say ""
  _say "個別に変えるとき: policy set analyst workflow=none cdp=none"
}

cmd_policy_set() {
  local base="${1:-}"; shift || true
  local spec; spec="$(_preset "$base")" || { _ng "不明なプリセット: '$base'（readonly / analyst / wf-ops / marketing / full / none）"; return 1; }
  local kv k v
  for kv in "$@"; do
    k="${kv%%=*}"; v="${kv#*=}"
    case " $POLICY_CATS " in *" $k "*) ;; *) _ng "不明なカテゴリ: ${k}（${POLICY_CATS}）"; return 1 ;; esac
    case "$v" in none|read|write) ;; *) _ng "不明な水準: ${v}（none / read / write）"; return 1 ;; esac
    [ "$k" = admin ] && [ "$v" = write ] && { _ng "admin は read までです"; return 1; }
    spec="$(printf '%s\n' $spec | sed "s/^$k=.*/$k=$v/" | tr '\n' ' ')"
  done
  {
    echo "# td-claude2tdx-connect の操作範囲（setup-tdx.sh policy set が書き込む）"
    echo "# none = 不可 / read = 参照のみ / write = 参照・更新（更新は都度の了承が必要）"
    echo "# preset: $base${*:+ / 変更: $*}"
    echo "# updated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf '%s\n' $spec
  } > "$TD_WORKDIR/tdx_policy.conf"
  _ok "操作範囲を tdx_policy.conf に記録しました"
  cmd_policy_show
}

_pol_get() { sed -n "s/^$1=\([a-z]*\).*/\1/p" "$TD_WORKDIR/tdx_policy.conf" 2>/dev/null | tail -1; }

cmd_policy_show() {
  [ -f "$TD_WORKDIR/tdx_policy.conf" ] || { _na "操作範囲: 未設定（tdx は status 以外すべて拒否）"; return 1; }
  _say "== 操作範囲（tdx_policy.conf）"
  _say "| 項目 | 設定 |"
  _say "|---|---|"
  local c
  for c in $POLICY_CATS; do _say "| $(_cat_label "$c") | $(_lvl_label "$(_pol_get "$c")") |"; done
  _say ""
  _say "== Treasure Data 側で合わせる設定（API キーのユーザーのポリシー）"
  _say "クライアント側の制限は誤操作防止です。同じ範囲を TD の Policies でも設定してください（項目名はコンソールの表示に合わせて読み替え）。"
  case "$(_pol_get data)" in
    write) _say "- データベース: 対象 DB に限定してフルアクセス（書き込み SQL を使うため）" ;;
    read)  _say "- データベース: 対象 DB に限定して Query Only（参照のみ）" ;;
    *)     _say "- データベース: 権限を付与しない" ;;
  esac
  case "$(_pol_get workflow)" in
    write) _say "- ワークフロー: 対象プロジェクトの編集・実行を許可" ;;
    read)  _say "- ワークフロー: 参照（View）のみ" ;;
    *)     _say "- ワークフロー: 権限を付与しない" ;;
  esac
  local c2
  for c2 in cdp journey engage; do
    case "$(_pol_get $c2)" in
      write) _say "- $(_cat_label $c2): 対象の親セグメント / ワークスペースで編集を許可" ;;
      read)  _say "- $(_cat_label $c2): 参照のみ" ;;
      *)     _say "- $(_cat_label $c2): 権限を付与しない" ;;
    esac
  done
}

cmd_policy() {
  case "${1:-show}" in
    presets) cmd_policy_presets ;;
    set) shift; cmd_policy_set "$@" ;;
    show) cmd_policy_show ;;
    *) _say "usage: setup-tdx.sh policy presets | set <プリセット> [カテゴリ=水準 ...] | show"; return 1 ;;
  esac
}

# ---------- verify ----------
cmd_verify() {
  local fail=0 mode="${CONF_MODE:-}"
  _say "== 検証（プラン ${mode:-未設定} / リージョン ${SITE}）"
  [ -n "$mode" ] || { _ng "tdx_setup.conf がありません。先に install を実行してください"; return 1; }

  # 1. 通信
  local h c
  for h in "$H_API" "$H_CDP" "$H_WF"; do
    c="$(_http "https://$h/")"
    if [ "$c" != 000 ]; then _ok "到達: $h"; _report_cert_chain "$h" || fail=1
    else _ng "到達できない: $h"; fail=1; fi
  done
  _tls_env_ok || fail=1

  # 2. 本体と版
  _load_key
  if [ "$mode" = D ]; then
    if [ -x "$TD_WORKDIR/td-api.sh" ]; then _ok "td-api.sh あり"; else _ng "td-api.sh が無い"; fail=1; fi
    local out; out="$(TD_WORKDIR="$TD_WORKDIR" "$TD_WORKDIR/td-api.sh" status 2>&1)"
    if printf '%s' "$out" | grep -q 'auth: OK'; then _ok "$(printf '%s' "$out" | grep 'auth: OK')"
    else _ng "認証: $(printf '%s' "$out" | tail -1)"; fail=1; fi
  else
    if _node_ok; then _ok "Node.js $(node -v)（セキュリティ修正版）"
    else _ng "${NODE_WHY}（${NODE_REQ_TEXT} が必要。用意できなければプラン D）"; fail=1; fi
    export PATH="$TD_WORKDIR/runtime/bin:$PATH"
    local tx="$TD_WORKDIR/runtime/bin/tdx"  # PATH 上の別の tdx を検証しないよう実体を固定する
    local v; v="$("$tx" --version 2>/dev/null | head -1)"
    if printf '%s' "$v" | grep -q "tdx $TDX_VERSION"; then _ok "版: $v"
    else _ng "版: '${v:-不明}'（期待: ${TDX_VERSION}）"; fail=1; fi

    # 3. 認証
    if "$tx" --site "$SITE" auth status >/dev/null 2>&1; then _ok "認証: 成功"
    else _ng "認証: 失敗（キー / リージョンを確認。tdx --site $SITE auth status で詳細）"; fail=1; fi

    # 4. 権限範囲（参照のみで確認。操作範囲で不可のものは確認しない）
    local n
    if [ "$(_pol_get data)" = read ] || [ "$(_pol_get data)" = write ]; then
      n="$("$tx" --site "$SITE" databases --jsonl 2>/dev/null | grep -c '^[[:space:]]*{')"
      if [ "${n:-0}" -gt 0 ]; then _ok "見えるデータベース: $n 件（多すぎる場合は TD のポリシーで絞る）"
      else _ng "データベースが1件も見えない（権限かリージョンを確認）"; fail=1; fi
    else _na "データベース: 操作範囲で不可のため確認しない"; fi
    if [ "$(_pol_get workflow)" = read ] || [ "$(_pol_get workflow)" = write ]; then
      if "$tx" --site "$SITE" wf projects >/dev/null 2>&1; then _ok "ワークフロー API: 参照可"
      else _ng "ワークフロー API: 参照できない"; fail=1; fi
    else _na "ワークフロー: 操作範囲で不可のため確認しない"; fi
  fi

  # 5. 操作範囲の強制
  if [ ! -f "$TD_WORKDIR/tdx_policy.conf" ]; then
    _ng "操作範囲が未設定（policy set を実行）"; fail=1
  else
    if [ "$mode" != D ]; then
      if grep -q 'tdx-guard.sh' "$TD_WORKDIR/runtime/bin/tdx" 2>/dev/null && [ -f "$TD_WORKDIR/tdx-guard.sh" ]; then
        _ok "ガード: runtime/bin/tdx は tdx-guard.sh 経由"
      else _ng "ガード: runtime/bin/tdx がガードを経由していない（install をやり直す）"; fail=1; fi
    fi
    # 各カテゴリの代表操作で、ガードが設定どおりに判定するか
    local probe exp got cat rd wr chk
    local pfail=0
    for cat in data workflow cdp journey engage; do
      case "$cat" in
        data)     rd="query select 1";             wr="query insert into t select 1" ;;
        workflow) rd="wf projects";                wr="wf push ." ;;
        cdp)      rd="segments";                   wr="sg push" ;;
        journey)  rd="journeys";                   wr="journey push" ;;
        engage)   rd="engage campaigns";           wr="engage campaign launch x" ;;
      esac
      local lv; lv="$(_pol_get $cat)"; lv="${lv:-none}"
      for probe in read write; do
        [ $probe = read ] && chk="$rd" || chk="$wr"
        exp=deny
        { [ $probe = read ] && [ "$lv" != none ]; } && exp=allow
        { [ $probe = write ] && [ "$lv" = write ]; } && exp=allow
        if [ "$mode" = D ]; then got="$(_tdapi_check $cat $probe)"
        else got="$(TD_ALLOW_WRITE=1 TD_WORKDIR="$TD_WORKDIR" bash "$TD_WORKDIR/tdx-guard.sh" --check $chk | cut -f1)"; fi
        [ -z "$got" ] && continue
        if [ "$got" != "$exp" ]; then _ng "ガード判定: $cat/$probe が ${got}（期待 ${exp}）"; pfail=1; fail=1; fi
      done
    done
    [ $pfail = 0 ] && _ok "ガード判定: 操作範囲どおり（$(for c in $POLICY_CATS; do printf '%s=%s ' $c "$(_pol_get $c)"; done)）"
  fi

  _say ""
  if [ $fail = 0 ]; then _say "検証結果: 合格"; _say "VERIFY=PASS"; return 0
  else _say "検証結果: 不合格（[NG] の項目を確認）"; _say "VERIFY=FAIL"; return 1; fi
}

_tdapi_check() {  # プラン D: td-api.sh の判定（未対応カテゴリは空）
  local cmd
  case "$1/$2" in
    data/read) cmd="query db 'select 1'" ;; data/write) cmd="query db 'insert into t select 1'" ;;
    workflow/read) cmd="wf-projects" ;; cdp/read) cmd="parent-segments" ;;
    *) return 0 ;;
  esac
  TD_ALLOW_WRITE=1 TD_WORKDIR="$TD_WORKDIR" eval "\"$TD_WORKDIR/td-api.sh\" --check $cmd" 2>/dev/null | cut -f1
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
  # zsh から source されても動くよう、単語分割に頼らず列挙する
  if [ -f "$TD_WORKDIR/tdx_policy.conf" ]; then
    _say "policy: data=$(_pol_get data) workflow=$(_pol_get workflow) cdp=$(_pol_get cdp) journey=$(_pol_get journey) engage=$(_pol_get engage) ai=$(_pol_get ai) admin=$(_pol_get admin)"
  else
    _say "policy: 未設定（tdx は status 以外すべて拒否）"
  fi
  if [ "${CONF_MODE:-}" != D ] && ! _node_ok; then _say "warning: ${NODE_WHY}。tdx-guard は実行を止めます（${NODE_REQ_TEXT}）"; fi
  # runtime/ が無いときに PATH 上の別の tdx（ガードを通らない）が使われないよう、ガード経由の実体に固定する
  _TDX_SHIM="$TD_WORKDIR/runtime/bin/tdx"
  tdx() {
    [ -x "$_TDX_SHIM" ] || { echo "tdx が導入されていません（$_TDX_SHIM）。setup-tdx.sh install を実行してください" >&2; return 127; }
    "$_TDX_SHIM" "$@"
  }
  [ -x "$_TDX_SHIM" ] && tdx --version 2>/dev/null | head -1
  return 0
fi

case "${1:-plan}" in
  plan)    cmd_plan ;;
  install) shift; cmd_install "$@" ;;
  verify)  cmd_verify ;;
  policy)  shift; cmd_policy "$@" ;;
  *) sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'; exit 1 ;;
esac
