#!/usr/bin/env bash
# 作業フォルダに tdx を用意し、API キーを読み込む。
#
#   source ./setup-tdx.sh                  # 既定の作業フォルダを探して使う
#   TD_WORKDIR=~/TreasureAI source ./setup-tdx.sh
#
# 作業フォルダの構成:
#   <workdir>/tdx_key.txt                  1行目: APIキー / 2行目: リージョン（任意、既定 us01）
#   <workdir>/tdx-bundle-<ver>.tgz         検証済みのオフライン一式（scripts/build-tdx-bundle.sh で作る）
#   <workdir>/tdx-bundle-<ver>.tgz.sha256  その SHA-256
#   <workdir>/runtime/                     展開先。接続フォルダ内に置くのでセッションをまたいで残る
#
# tdx の入手経路（上から順に使う）:
#   1. runtime/bin/tdx が既にある → そのまま使う
#   2. tdx-bundle-*.tgz がある     → SHA-256 を照合して展開。npm には一切アクセスしない
#   3. どちらも無い                → 何もインストールしない。td-api.sh（curl のみ）を案内する
#      ※ 明示的に TDX_ALLOW_NPM=1 を付けたときだけ npm から入れる（バージョン完全固定・scripts 無効）
#        社内ミラーを使う場合は NPM_REGISTRY=<URL> も指定する

set -uo pipefail

TDX_VERSION="${TDX_VERSION:-2026.9.0}"

_fail() { echo "$*"; return 1 2>/dev/null || exit 1; }

# 作業フォルダの決定: TD_WORKDIR > スクリプトと同階層 > mnt 配下を検索
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
if [ -z "${TD_WORKDIR:-}" ]; then
  if [ -s "$SCRIPT_DIR/tdx_key.txt" ]; then
    TD_WORKDIR="$SCRIPT_DIR"
  else
    _found="$(find "$HOME/mnt" -maxdepth 4 -name 'tdx_key.txt' -size +0 2>/dev/null | head -1)"
    [ -n "$_found" ] && TD_WORKDIR="$(dirname "$_found")"
  fi
fi

if [ -z "${TD_WORKDIR:-}" ] || [ ! -s "$TD_WORKDIR/tdx_key.txt" ]; then
  echo "APIキーが見つかりません。"
  echo "作業フォルダ（既定: TreasureAI）に tdx_key.txt を作り、1行目にキーを書いてください。"
  echo "場所を明示する場合: TD_WORKDIR=<パス> source ./setup-tdx.sh"
  return 1 2>/dev/null || exit 1
fi

export PATH="$TD_WORKDIR/runtime/bin:$PATH"

_sha256() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1"; else shasum -a 256 "$1"; fi | awk '{print $1}'; }

if ! command -v tdx >/dev/null 2>&1; then
  _bundle="$(ls -1 "$TD_WORKDIR"/tdx-bundle-*.tgz 2>/dev/null | sort -V | tail -1)"
  if [ -n "$_bundle" ]; then
    [ -s "$_bundle.sha256" ] || { _fail "$(basename "$_bundle").sha256 がありません。一式と一緒に置いてください"; return 1 2>/dev/null || exit 1; }
    _want="$(awk '{print $1}' "$_bundle.sha256")"
    _got="$(_sha256 "$_bundle")"
    if [ "$_want" != "$_got" ]; then
      _fail "SHA-256 が一致しません。一式が改変・破損している可能性があるため展開しません"
      return 1 2>/dev/null || exit 1
    fi
    echo "$(basename "$_bundle") を検証しました（SHA-256 一致）。runtime/ に展開します"
    mkdir -p "$TD_WORKDIR/runtime" && tar xzf "$_bundle" -C "$TD_WORKDIR/runtime" \
      || { _fail "展開に失敗しました"; return 1 2>/dev/null || exit 1; }
  elif [ "${TDX_ALLOW_NPM:-0}" = 1 ]; then
    echo "TDX_ALLOW_NPM=1 のため npm から tdx $TDX_VERSION を入れます（scripts 無効・optional 除外）"
    _reg=(); [ -n "${NPM_REGISTRY:-}" ] && _reg=(--registry "$NPM_REGISTRY")
    npm i -g --prefix "$TD_WORKDIR/runtime" ${_reg[@]+"${_reg[@]}"} --ignore-scripts --omit=optional \
      --no-fund --no-audit "@treasuredata/tdx@$TDX_VERSION" >/dev/null 2>&1 \
      || { _fail "インストールに失敗しました"; return 1 2>/dev/null || exit 1; }
  else
    echo "tdx はインストールしていません（npm へのアクセスは既定で行いません）。"
    echo "  - そのまま使う: 同梱の td-api.sh（curl のみ。Treasure Data のドメインにしか通信しない）"
    echo "  - tdx を使う  : scripts/build-tdx-bundle.sh で作った tdx-bundle-*.tgz と .sha256 を $TD_WORKDIR に置く"
    return 2 2>/dev/null || exit 2
  fi
fi

export TDX_API_KEY="$(sed -n '1p' "$TD_WORKDIR/tdx_key.txt" | tr -d '[:space:]')"
TDX_SITE="$(sed -n '2p' "$TD_WORKDIR/tdx_key.txt" | tr -d '[:space:]')"
export TDX_SITE="${TDX_SITE:-us01}"

echo "workdir: $TD_WORKDIR"
echo "$(tdx --version 2>/dev/null | head -1)"
tdx --site "$TDX_SITE" auth status 2>&1 | sed -n '2,6p'
