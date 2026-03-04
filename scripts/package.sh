#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  scripts/package.sh --version <version> [options]

Options:
  --version <version>          Release version, e.g. 1.0.0 (required)
  --app-name <name>            App bundle name (default: EchoType)
  --binary-name <name>         Swift executable target name (default: echotype)
  --bundle-id <id>             CFBundleIdentifier (default: com.smoose.echotype)
  --icon-path <path>           App icon .icns path relative to repo root (default: docs/assets/logo/AppIcon.icns)
  --output-dir <path>          Output directory (default: dist)
  --sign-identity <identity>   codesign identity (default: - for ad-hoc)
EOF
}

die() {
  echo "Error: $*" >&2
  exit 1
}

VERSION=""
APP_NAME="EchoType"
BINARY_NAME="echotype"
BUNDLE_ID="com.smoose.echotype"
ICON_PATH="docs/assets/logo/AppIcon.icns"
OUTPUT_DIR="dist"
SIGN_IDENTITY="-"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      VERSION="${2:-}"
      shift 2
      ;;
    --app-name)
      APP_NAME="${2:-}"
      shift 2
      ;;
    --binary-name)
      BINARY_NAME="${2:-}"
      shift 2
      ;;
    --bundle-id)
      BUNDLE_ID="${2:-}"
      shift 2
      ;;
    --icon-path)
      ICON_PATH="${2:-}"
      shift 2
      ;;
    --output-dir)
      OUTPUT_DIR="${2:-}"
      shift 2
      ;;
    --sign-identity)
      SIGN_IDENTITY="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "Unknown argument: $1"
      ;;
  esac
done

[[ -n "$VERSION" ]] || die "--version is required"

command -v swift >/dev/null 2>&1 || die "swift is not installed"
command -v ditto >/dev/null 2>&1 || die "ditto is not available"
command -v hdiutil >/dev/null 2>&1 || die "hdiutil is not available"
command -v codesign >/dev/null 2>&1 || die "codesign is not available"
command -v shasum >/dev/null 2>&1 || die "shasum is not available"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_ABS="${ROOT_DIR}/${OUTPUT_DIR}"
APP_BUNDLE="${OUTPUT_ABS}/${APP_NAME}.app"
APP_BINARY="${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
ICON_NAME="${APP_NAME}.icns"
ICON_ABS="${ROOT_DIR}/${ICON_PATH}"
ZIP_PATH="${OUTPUT_ABS}/${APP_NAME}-${VERSION}.macos.zip"
DMG_PATH="${OUTPUT_ABS}/${APP_NAME}-${VERSION}.dmg"
CHECKSUM_PATH="${OUTPUT_ABS}/${APP_NAME}-${VERSION}.checksums.txt"

echo "==> Building ${BINARY_NAME} (release)"
(
  cd "$ROOT_DIR"
  swift build -c release
)

BINARY_PATH="$(find "${ROOT_DIR}/.build" -type f -path "*/release/${BINARY_NAME}" | head -n 1)"
[[ -n "${BINARY_PATH}" ]] || die "Unable to find release binary for ${BINARY_NAME}"
BUILD_RELEASE_DIR="$(dirname "${BINARY_PATH}")"

echo "==> Preparing app bundle at ${APP_BUNDLE}"
rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS" "${APP_BUNDLE}/Contents/Resources"
cp "${BINARY_PATH}" "${APP_BINARY}"
chmod +x "${APP_BINARY}"

for bundle in "${BUILD_RELEASE_DIR}"/*.bundle; do
  [[ -d "${bundle}" ]] || continue
  cp -R "${bundle}" "${APP_BUNDLE}/Contents/"
done

ICON_PLIST_ENTRY=""
if [[ -f "${ICON_ABS}" ]]; then
  cp "${ICON_ABS}" "${APP_BUNDLE}/Contents/Resources/${ICON_NAME}"
  ICON_PLIST_ENTRY="  <key>CFBundleIconFile</key><string>${ICON_NAME}</string>"
else
  echo "Warning: icon file not found, packaging without app icon: ${ICON_ABS}" >&2
fi

cat > "${APP_BUNDLE}/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>${APP_NAME}</string>
  <key>CFBundleDisplayName</key><string>${APP_NAME}</string>
  <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
  <key>CFBundleVersion</key><string>${VERSION}</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleExecutable</key><string>${APP_NAME}</string>
  <key>CFBundlePackageType</key><string>APPL</string>
${ICON_PLIST_ENTRY}
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSMicrophoneUsageDescription</key><string>EchoType needs microphone access for speech transcription.</string>
</dict>
</plist>
EOF

echo "==> Signing app bundle"
codesign --force --deep --sign "${SIGN_IDENTITY}" "${APP_BUNDLE}"
codesign --verify --deep --strict "${APP_BUNDLE}"

echo "==> Creating zip archive"
rm -f "${ZIP_PATH}"
ditto -c -k --keepParent "${APP_BUNDLE}" "${ZIP_PATH}"

echo "==> Creating dmg installer"
DMG_STAGE_DIR="$(mktemp -d "${OUTPUT_ABS}/dmg-stage.XXXXXX")"
cleanup() {
  rm -rf "${DMG_STAGE_DIR}"
}
trap cleanup EXIT

cp -R "${APP_BUNDLE}" "${DMG_STAGE_DIR}/"
ln -s /Applications "${DMG_STAGE_DIR}/Applications"
rm -f "${DMG_PATH}"
hdiutil create \
  -volname "${APP_NAME}" \
  -srcfolder "${DMG_STAGE_DIR}" \
  -ov \
  -format UDZO \
  "${DMG_PATH}" >/dev/null

echo "==> Writing checksums"
shasum -a 256 "${ZIP_PATH}" "${DMG_PATH}" > "${CHECKSUM_PATH}"

echo "Done."
echo "  App:       ${APP_BUNDLE}"
echo "  Zip:       ${ZIP_PATH}"
echo "  Dmg:       ${DMG_PATH}"
echo "  Checksums: ${CHECKSUM_PATH}"
