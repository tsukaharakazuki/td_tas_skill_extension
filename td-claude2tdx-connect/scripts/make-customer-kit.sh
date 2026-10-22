#!/usr/bin/env bash
# make-customer-kit.sh — npm を許可できないお客様向けに、配布用 zip を1本作る。
#
# Mac の「ターミナル」で、td_tas_skill_extension をクローンしたフォルダから実行する。
#   bash td-claude2tdx-connect/scripts/make-customer-kit.sh [バージョン] [出力先]
#   例: bash td-claude2tdx-connect/scripts/make-customer-kit.sh 2026.9.0 ~/Desktop
#
# やること:
#   1. build-tdx-bundle.sh で署名検証つきの一式（tgz と .sha256）を作る
#   2. お客様の作業フォルダ TreasureAI/ に必要なものを並べる
#        setup-tdx.sh / tdx-guard.sh / td-api.sh / 一式 / 空の tdx_key.txt
#   3. 審査資料を review/ にまとめ、README.txt を添えて zip にする
#
# zip 内のファイル名は ASCII のみ（Windows のエクスプローラーで文字化けしないため）。

set -euo pipefail

VER="${1:-2026.9.0}"
OUT="$(cd "${2:-.}" && pwd)"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN="$(cd "$HERE/.." && pwd)"

for f in setup-tdx.sh tdx-guard.sh td-api.sh; do
  [ -f "$PLUGIN/$f" ] || { echo "$PLUGIN/$f が見つかりません"; exit 1; }
done
[ -f "$HERE/README.customer.txt" ] || { echo "$HERE/README.customer.txt が見つかりません"; exit 1; }
command -v zip >/dev/null || { echo "zip コマンドが必要です"; exit 1; }

STAGE="$(mktemp -d)"; trap 'rm -rf "$STAGE"' EXIT
KIT="$STAGE/td-connect-kit"
mkdir -p "$KIT/TreasureAI" "$KIT/review" "$STAGE/build"

echo "== 一式を作る（署名検証あり）"
bash "$HERE/build-tdx-bundle.sh" "$VER" "$STAGE/build" || { echo "一式の作成に失敗しました。上のエラーを確認してください"; exit 1; }

echo "== キットを組み立てる"
cp "$STAGE/build/tdx-bundle-$VER.tgz" "$STAGE/build/tdx-bundle-$VER.tgz.sha256" "$KIT/TreasureAI/"
cp "$PLUGIN/setup-tdx.sh" "$PLUGIN/tdx-guard.sh" "$PLUGIN/td-api.sh" "$KIT/TreasureAI/"
: > "$KIT/TreasureAI/tdx_key.txt"
cp "$STAGE/build/tdx-bundle-$VER.package-lock.json" "$KIT/review/package-lock.json"
cp "$STAGE/build/tdx-bundle-$VER.audit.txt"         "$KIT/review/audit.txt"
cp "$STAGE/build/tdx-bundle-$VER.signatures.txt"    "$KIT/review/signatures.txt"
[ -f "$STAGE/build/tdx-bundle-$VER.sbom.cdx.json" ] && cp "$STAGE/build/tdx-bundle-$VER.sbom.cdx.json" "$KIT/review/sbom.cdx.json"
# Windows のメモ帳でも崩れないよう CRLF にする
sed 's/$/\r/' "$HERE/README.customer.txt" > "$KIT/README.txt"

echo "== 照合"
( cd "$KIT/TreasureAI" && if command -v sha256sum >/dev/null; then sha256sum -c "tdx-bundle-$VER.tgz.sha256"; else shasum -a 256 -c "tdx-bundle-$VER.tgz.sha256"; fi )

ZIP="$OUT/td-connect-kit-$VER.zip"
rm -f "$ZIP"
( cd "$STAGE" && zip -qrX "$ZIP" td-connect-kit )

echo
echo "できました: $ZIP"
echo "一式の SHA-256: $(awk '{print $1}' "$KIT/TreasureAI/tdx-bundle-$VER.tgz.sha256")"
echo "この値をお客様にメールなど別経路でも伝えると、受け取った一式の照合に使えます。"
