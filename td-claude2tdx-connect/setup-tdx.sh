#!/usr/bin/env bash
# Cowork のセッション用 tdx セットアップ。
# セッションごとに使い捨てられる VM に tdx を入れ直し、認証を通すためのもの。
#
#   source ./setup-tdx.sh          # tdx を PATH に通し、TDX_API_KEY を読み込む
#
# API キーは同じディレクトリの tdx_key.txt から読む（.gitignore 済み、コミットされない）。

set -uo pipefail

TDX_VERSION="${TDX_VERSION:-2026.9.0}"
TDX_SITE="${TDX_SITE:-us01}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"

# キーファイルはスクリプトと同じ階層、無ければリポジトリ直下を見る。
# TDX_KEY_FILE で明示指定も可。
if [ -z "${TDX_KEY_FILE:-}" ]; then
  if [ -s "$SCRIPT_DIR/tdx_key.txt" ]; then
    TDX_KEY_FILE="$SCRIPT_DIR/tdx_key.txt"
  else
    TDX_KEY_FILE="$SCRIPT_DIR/../tdx_key.txt"
  fi
fi
KEY_FILE="$TDX_KEY_FILE"

# npm の -g 先を書き込めるところに向ける（/usr は権限がない）
if [ "$(npm config get prefix)" != "$HOME/.npm-global" ]; then
  npm config set prefix "$HOME/.npm-global" >/dev/null
fi
export PATH="$HOME/.npm-global/bin:$PATH"

if ! command -v tdx >/dev/null 2>&1; then
  echo "tdx $TDX_VERSION をインストールしています..."
  npm i -g "@treasuredata/tdx@$TDX_VERSION" >/dev/null 2>&1 \
    || { echo "インストールに失敗しました"; return 1 2>/dev/null || exit 1; }
fi

if [ ! -s "$KEY_FILE" ]; then
  echo "APIキーがありません: $KEY_FILE に Master Key を1行で書いてください"
  return 1 2>/dev/null || exit 1
fi

export TDX_API_KEY="$(tr -d '[:space:]' < "$KEY_FILE")"
export TDX_SITE

echo "$(tdx --version 2>/dev/null | head -1)"
tdx --site "$TDX_SITE" auth status 2>&1 | sed -n '2,6p'
