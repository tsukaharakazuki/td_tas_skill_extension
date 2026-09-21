#!/usr/bin/env bash
# 作業フォルダに tdx を用意し、API キーを読み込む。
#
#   source ./setup-tdx.sh                  # 既定の作業フォルダを探して使う
#   TD_WORKDIR=~/TreasureAI source ./setup-tdx.sh
#
# 作業フォルダの構成:
#   <workdir>/tdx_key.txt   1行目: APIキー / 2行目: リージョン（任意、既定 us01）
#   <workdir>/runtime/      tdx 本体。接続フォルダ内に置くのでセッションをまたいで残る

set -uo pipefail

TDX_VERSION="${TDX_VERSION:-2026.9.0}"

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

if ! command -v tdx >/dev/null 2>&1; then
  echo "tdx $TDX_VERSION を $TD_WORKDIR/runtime に入れています（初回のみ、60秒ほど）..."
  npm i -g --prefix "$TD_WORKDIR/runtime" "@treasuredata/tdx@$TDX_VERSION" >/dev/null 2>&1 \
    || { echo "インストールに失敗しました"; return 1 2>/dev/null || exit 1; }
fi

export TDX_API_KEY="$(sed -n '1p' "$TD_WORKDIR/tdx_key.txt" | tr -d '[:space:]')"
TDX_SITE="$(sed -n '2p' "$TD_WORKDIR/tdx_key.txt" | tr -d '[:space:]')"
export TDX_SITE="${TDX_SITE:-us01}"

echo "workdir: $TD_WORKDIR"
echo "$(tdx --version 2>/dev/null | head -1)"
tdx --site "$TDX_SITE" auth status 2>&1 | sed -n '2,6p'
