#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  scripts/release.sh --version <version> --repo <owner/repo> [options]

Options:
  --version <version>          Release version, e.g. 1.0.0 (required)
  --repo <owner/repo>          GitHub repository, e.g. smoosex/echo-type (required)
  --tag-prefix <prefix>        Release tag prefix (default: v)
  --dist-dir <path>            Local dist directory (default: dist)
  --app-name <name>            App display name (default: EchoType)
  --token <token>              Homebrew cask token (default: echotype)
  --tap-repo <owner/repo>      Optional Homebrew tap repository to update
  --skip-tap                   Skip syncing Homebrew tap even if --tap-repo is provided

Notes:
  - Tap sync uses SSH (git@github.com:...). Ensure your GitHub SSH key is configured.
EOF
}

die() {
  echo "Error: $*" >&2
  exit 1
}

VERSION=""
REPO=""
TAG_PREFIX="v"
DIST_DIR="dist"
APP_NAME="EchoType"
TOKEN="echotype"
TAP_REPO=""
SKIP_TAP=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      VERSION="${2:-}"
      shift 2
      ;;
    --repo)
      REPO="${2:-}"
      shift 2
      ;;
    --tag-prefix)
      TAG_PREFIX="${2:-}"
      shift 2
      ;;
    --dist-dir)
      DIST_DIR="${2:-}"
      shift 2
      ;;
    --app-name)
      APP_NAME="${2:-}"
      shift 2
      ;;
    --token)
      TOKEN="${2:-}"
      shift 2
      ;;
    --tap-repo)
      TAP_REPO="${2:-}"
      shift 2
      ;;
    --skip-tap)
      SKIP_TAP=true
      shift
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
[[ -n "$REPO" ]] || die "--repo is required"

command -v gh >/dev/null 2>&1 || die "gh CLI is required (https://cli.github.com/)"
command -v shasum >/dev/null 2>&1 || die "shasum is required"
command -v git >/dev/null 2>&1 || die "git is required"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_ABS="${ROOT_DIR}/${DIST_DIR}"
ZIP_PATH="${DIST_ABS}/${APP_NAME}-${VERSION}.macos.zip"
DMG_PATH="${DIST_ABS}/${APP_NAME}-${VERSION}.dmg"
CHECKSUM_PATH="${DIST_ABS}/${APP_NAME}-${VERSION}.checksums.txt"
CASK_PATH="${DIST_ABS}/${TOKEN}.rb"
TAG_NAME="${TAG_PREFIX}${VERSION}"

[[ -f "${ZIP_PATH}" ]] || die "Missing asset: ${ZIP_PATH}"
[[ -f "${DMG_PATH}" ]] || die "Missing asset: ${DMG_PATH}"
[[ -f "${CHECKSUM_PATH}" ]] || die "Missing asset: ${CHECKSUM_PATH}"

echo "==> Verifying GitHub authentication"
gh auth status >/dev/null

echo "==> Generating Homebrew cask from local dmg checksum"
DMG_SHA256="$(shasum -a 256 "${DMG_PATH}" | awk '{print $1}')"
if [[ ! "${DMG_SHA256}" =~ ^[0-9a-fA-F]{64}$ ]]; then
  die "Invalid dmg checksum: ${DMG_SHA256}"
fi
mkdir -p "${DIST_ABS}"
cat > "${CASK_PATH}" <<EOF
cask "${TOKEN}" do
  version "${VERSION}"
  sha256 "${DMG_SHA256}"

  url "https://github.com/${REPO}/releases/download/${TAG_PREFIX}${VERSION}/${APP_NAME}-${VERSION}.dmg"
  name "${APP_NAME}"
  desc "Offline speech-to-text menubar app for macOS"
  homepage "https://github.com/${REPO}"

  depends_on macos: ">= :ventura"

  app "${APP_NAME}.app"
end
EOF

echo "==> Creating GitHub release when missing"
if gh release view "${TAG_NAME}" --repo "${REPO}" >/dev/null 2>&1; then
  echo "Release ${TAG_NAME} already exists"
else
  gh release create "${TAG_NAME}" \
    --repo "${REPO}" \
    --title "${APP_NAME} ${VERSION}" \
    --notes "Release ${VERSION}"
fi

echo "==> Uploading local artifacts to GitHub release"
gh release upload "${TAG_NAME}" \
  "${ZIP_PATH}" \
  "${DMG_PATH}" \
  "${CHECKSUM_PATH}" \
  "${CASK_PATH}" \
  --clobber \
  --repo "${REPO}"

if [[ "${SKIP_TAP}" == true ]]; then
  echo "==> Skip tap sync (--skip-tap)"
  exit 0
fi

if [[ -z "${TAP_REPO}" ]]; then
  echo "==> No --tap-repo provided; skip Homebrew tap sync"
  exit 0
fi

echo "==> Syncing cask to tap repo: ${TAP_REPO}"
TMP_DIR="$(mktemp -d)"
cleanup() {
  rm -rf "${TMP_DIR}"
}
trap cleanup EXIT

TAP_SSH_URL="git@github.com:${TAP_REPO}.git"
if ! git ls-remote "${TAP_SSH_URL}" >/dev/null 2>&1; then
  die "Cannot access ${TAP_SSH_URL} via SSH. Configure your GitHub SSH key first."
fi

git clone "${TAP_SSH_URL}" "${TMP_DIR}/tap"
mkdir -p "${TMP_DIR}/tap/Casks"
cp "${CASK_PATH}" "${TMP_DIR}/tap/Casks/${TOKEN}.rb"

(
  cd "${TMP_DIR}/tap"
  if git diff --quiet -- "Casks/${TOKEN}.rb"; then
    echo "No tap changes detected"
    exit 0
  fi
  git add "Casks/${TOKEN}.rb"
  git commit -m "update ${TOKEN} cask for v${VERSION}"
  git push origin HEAD:main
)

echo "Done."
echo "  Release: https://github.com/${REPO}/releases/tag/${TAG_NAME}"
