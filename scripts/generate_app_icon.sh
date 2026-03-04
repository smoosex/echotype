#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  scripts/generate_app_icon.sh [options]

Options:
  --source <path>   Source SVG path (default: docs/assets/logo/echotype-logo-primary.svg)
  --output <path>   Output icns path (default: docs/assets/logo/AppIcon.icns)
  --name <name>     Iconset directory name (default: EchoType)
EOF
}

die() {
  echo "Error: $*" >&2
  exit 1
}

SOURCE_SVG="docs/assets/logo/echotype-logo-primary.svg"
OUTPUT_ICNS="docs/assets/logo/AppIcon.icns"
ICONSET_NAME="EchoType"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source)
      SOURCE_SVG="${2:-}"
      shift 2
      ;;
    --output)
      OUTPUT_ICNS="${2:-}"
      shift 2
      ;;
    --name)
      ICONSET_NAME="${2:-}"
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

command -v qlmanage >/dev/null 2>&1 || die "qlmanage is not available"
command -v sips >/dev/null 2>&1 || die "sips is not available"
command -v iconutil >/dev/null 2>&1 || die "iconutil is not available"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_ABS="${ROOT_DIR}/${SOURCE_SVG}"
OUTPUT_ABS="${ROOT_DIR}/${OUTPUT_ICNS}"
OUTPUT_DIR="$(dirname "${OUTPUT_ABS}")"
ICONSET_ROOT="${OUTPUT_DIR}/iconset"
ICONSET_DIR="${ICONSET_ROOT}/${ICONSET_NAME}.iconset"
RENDERED_PNG="${ICONSET_ROOT}/$(basename "${SOURCE_SVG}").png"

[[ -f "${SOURCE_ABS}" ]] || die "Source SVG not found: ${SOURCE_ABS}"

mkdir -p "${ICONSET_ROOT}"
rm -rf "${ICONSET_DIR}"
mkdir -p "${ICONSET_DIR}"

echo "==> Rendering SVG to 1024x1024 PNG"
qlmanage -t -s 1024 -o "${ICONSET_ROOT}" "${SOURCE_ABS}" >/dev/null 2>&1 || \
  die "Failed to render SVG with qlmanage: ${SOURCE_ABS}"

[[ -f "${RENDERED_PNG}" ]] || die "Rendered PNG not found: ${RENDERED_PNG}"

echo "==> Building iconset: ${ICONSET_DIR}"
cp "${RENDERED_PNG}" "${ICONSET_DIR}/icon_512x512@2x.png"

for size in 16 32 128 256 512; do
  size2=$((size * 2))
  sips -z "${size}" "${size}" "${RENDERED_PNG}" --out "${ICONSET_DIR}/icon_${size}x${size}.png" >/dev/null
  sips -z "${size2}" "${size2}" "${RENDERED_PNG}" --out "${ICONSET_DIR}/icon_${size}x${size}@2x.png" >/dev/null
done

mkdir -p "${OUTPUT_DIR}"
echo "==> Generating icns: ${OUTPUT_ABS}"
iconutil -c icns "${ICONSET_DIR}" -o "${OUTPUT_ABS}" || \
  die "iconutil failed to generate icns"

echo "Done: ${OUTPUT_ABS}"
