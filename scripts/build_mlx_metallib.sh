#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/build_mlx_metallib.sh [debug|release]

Builds MLX's Metal shader library (`mlx.metallib`) for the current SwiftPM build
output directory. Run `swift build` first.

If the Metal toolchain is missing:
  xcodebuild -downloadComponent MetalToolchain
EOF
}

CONFIG="${1:-debug}"
if [[ "$CONFIG" != "debug" && "$CONFIG" != "release" ]]; then
  usage
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build"
OUT_DIR="$BUILD_DIR/$CONFIG"

if [[ -z "${DEVELOPER_DIR:-}" && -d "/Applications/Xcode.app/Contents/Developer" ]]; then
  export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
fi

if [[ ! -d "$OUT_DIR" ]]; then
  OUT_DIR="$(find "$BUILD_DIR" -maxdepth 3 -type d -path "*/$CONFIG" | head -n 1 || true)"
fi

if [[ -z "${OUT_DIR:-}" || ! -d "$OUT_DIR" ]]; then
  echo "error: failed to locate SwiftPM build output for config=$CONFIG" >&2
  exit 1
fi

MLX_SWIFT_DIR="$BUILD_DIR/checkouts/mlx-swift"
KERNELS_DIR="$MLX_SWIFT_DIR/Source/Cmlx/mlx/mlx/backend/metal/kernels"

if [[ ! -d "$KERNELS_DIR" ]]; then
  echo "error: missing MLX kernels at $KERNELS_DIR" >&2
  echo "hint: run swift build first so mlx-swift is checked out" >&2
  exit 1
fi

if ! xcrun -sdk macosx -f metal >/dev/null 2>&1; then
  echo "error: Xcode Metal Toolchain is missing." >&2
  echo "run: xcodebuild -downloadComponent MetalToolchain" >&2
  exit 1
fi

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/echotype-mlx-metallib.XXXXXX")"
cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

mapfile -t METAL_SRCS < <(find "$KERNELS_DIR" -type f -name '*.metal' ! -name '*_nax.metal' | LC_ALL=C sort)
if [[ "${#METAL_SRCS[@]}" -eq 0 ]]; then
  echo "error: no Metal sources found under $KERNELS_DIR" >&2
  exit 1
fi

AIR_FILES=()
TOTAL_SRCS="${#METAL_SRCS[@]}"
echo "==> Compiling ${TOTAL_SRCS} MLX Metal sources"

for INDEX in "${!METAL_SRCS[@]}"; do
  SRC="${METAL_SRCS[$INDEX]}"
  REL_PATH="${SRC#"$KERNELS_DIR/"}"
  printf '==> [%d/%d] %s\n' "$((INDEX + 1))" "$TOTAL_SRCS" "$REL_PATH"
  KEY="$(printf '%s' "$SRC" | shasum -a 256 | awk '{print $1}' | cut -c1-16)"
  OUT_AIR="$TMP_DIR/$KEY.air"
  xcrun -sdk macosx metal \
    -x metal \
    -Wall \
    -Wextra \
    -fno-fast-math \
    -Wno-c++17-extensions \
    -Wno-c++20-extensions \
    -c "$SRC" \
    -I"$KERNELS_DIR" \
    -I"$MLX_SWIFT_DIR/Source/Cmlx/mlx" \
    -o "$OUT_AIR"
  AIR_FILES+=("$OUT_AIR")
done

OUT_METALLIB="$OUT_DIR/mlx.metallib"
echo "==> Linking mlx.metallib"
xcrun -sdk macosx metallib "${AIR_FILES[@]}" -o "$OUT_METALLIB"
echo "OK: wrote $OUT_METALLIB"
