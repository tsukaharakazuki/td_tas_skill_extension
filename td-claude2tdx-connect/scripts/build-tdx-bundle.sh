#!/usr/bin/env bash
# build-tdx-bundle.sh — tdx を「検証済みのオフライン一式」に固めるスクリプト。
#
# Claude のセッションに registry.npmjs.org を許可できない環境向け。
# npm に到達できる管理された端末（または社内 npm ミラー）で 1 回だけ実行し、
# できた tgz と .sha256 を作業フォルダ（TreasureAI/）に置けば、
# setup-tdx.sh は npm に一切アクセスせずに tdx を展開する。
#
#   ./build-tdx-bundle.sh [バージョン] [出力先]
#   NPM_REGISTRY=https://npm.example.co.jp/ ./build-tdx-bundle.sh 2026.9.0 ~/TreasureAI
#
# やること:
#   1. バージョン完全固定で @treasuredata/tdx を入れる（依存も package-lock.json で固定）
#   2. install スクリプトを実行しない（--ignore-scripts）
#   3. OS 依存のネイティブモジュール（キーチェーン連携。APIキーを環境変数で渡すため不要）を除外し、
#      Mac で作っても Linux のセッションで動く純 JS の一式にする（--omit=optional）
#   4. npm audit signatures で全パッケージのレジストリ署名を検証する。失敗したら作らない
#   5. 既知の脆弱性レポート（npm audit）と SBOM（CycloneDX）を同梱する。セキュリティ審査に渡せる
#   6. tgz と SHA-256 を出力する

set -euo pipefail

VER="${1:-2026.9.0}"
OUT="$(cd "${2:-.}" && pwd)"
REG_ARGS=()
[ -n "${NPM_REGISTRY:-}" ] && REG_ARGS=(--registry "$NPM_REGISTRY")

command -v npm >/dev/null || { echo "npm が必要です（Node.js 22.12 以上）"; exit 1; }

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
cd "$WORK"
mkdir pkg && cd pkg
printf '{ "name": "tdx-bundle", "version": "%s", "private": true }\n' "$VER" > package.json

echo "== 1. インストール（@treasuredata/tdx@$VER, scripts 無効, optional 除外）"
npm install ${REG_ARGS[@]+"${REG_ARGS[@]}"} --save-exact --ignore-scripts --omit=optional \
  --no-fund --no-audit "@treasuredata/tdx@$VER"

echo "== 2. レジストリ署名の検証"
if [ "${SKIP_SIGNATURE_CHECK:-0}" = 1 ]; then
  echo "!! SKIP_SIGNATURE_CHECK=1 のため署名検証を省略しました。審査用の一式には使わないでください" | tee signature-check.txt
else
  # 署名の取得に registry.npmjs.org と tuf-repo-cdn.sigstore.dev への到達が必要（この端末だけ）
  npm audit signatures ${REG_ARGS[@]+"${REG_ARGS[@]}"} 2>&1 | tee signature-check.txt
  [ "${PIPESTATUS[0]}" = 0 ] || { echo "署名検証に失敗しました。一式は作りません"; exit 1; }
fi

echo "== 3. 脆弱性レポートと SBOM"
npm audit ${REG_ARGS[@]+"${REG_ARGS[@]}"} --omit=dev > audit-report.txt 2>&1 || true
npm sbom --sbom-format cyclonedx > sbom.cdx.json 2>/dev/null || echo "（npm sbom は npm 10.1 以降で利用可）"
find node_modules -name '*.node' -print > native-modules.txt || true

mkdir -p bin
cat > bin/tdx <<'SHIM'
#!/usr/bin/env bash
D="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec node "$D/node_modules/@treasuredata/tdx/dist/bin.js" "$@"
SHIM
chmod +x bin/tdx

echo "== 4. 動作確認"
TDX_API_KEY=0/dummy ./bin/tdx --version

echo "== 5. 梱包"
NAME="tdx-bundle-$VER.tgz"
tar czf "$OUT/$NAME" package.json package-lock.json bin node_modules audit-report.txt signature-check.txt sbom.cdx.json native-modules.txt 2>/dev/null \
  || tar czf "$OUT/$NAME" package.json package-lock.json bin node_modules audit-report.txt signature-check.txt native-modules.txt
cp package-lock.json "$OUT/tdx-bundle-$VER.package-lock.json"
cp audit-report.txt "$OUT/tdx-bundle-$VER.audit.txt"
cp signature-check.txt "$OUT/tdx-bundle-$VER.signatures.txt"
[ -s sbom.cdx.json ] && cp sbom.cdx.json "$OUT/tdx-bundle-$VER.sbom.cdx.json"
cd "$OUT"
if command -v sha256sum >/dev/null; then sha256sum "$NAME" > "$NAME.sha256"; else shasum -a 256 "$NAME" > "$NAME.sha256"; fi

echo
echo "できました:"
ls -l "$OUT"/tdx-bundle-"$VER"*
echo
echo "パッケージ数: $(grep -c '"node_modules/' "$OUT/tdx-bundle-$VER.package-lock.json")"
echo "$NAME と $NAME.sha256 を作業フォルダ（TreasureAI/）に置いてください。"
