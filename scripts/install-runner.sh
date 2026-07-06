#!/usr/bin/env bash
set -euo pipefail

RUNNER_REPO="${1:?RUNNER_REPO required (ex: saykai-systems/runner)}"
RUNNER_VERSION="${2:?RUNNER_VERSION required (ex: v1.0.1 or latest)}"
RUNNER_BASE_URL="${3:-}"   # optional, ex: https://downloads.saykai.com/runner
DEST_PATH="${4:?DEST_PATH required}"

OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
ARCH="$(uname -m)"

case "$OS" in
  linux|darwin) EXT="tar.gz"; BIN_NAME="saykai-runner" ;;
  mingw*|msys*|cygwin*)
    # windows-latest GitHub runners execute `shell: bash` steps via Git Bash,
    # where uname -s reports something like MINGW64_NT-10.0, not "windows".
    OS="windows"
    EXT="zip"
    BIN_NAME="saykai-runner.exe"
    ;;
  *)
    echo "Unsupported OS: ${OS}" >&2
    exit 1
    ;;
esac

case "$ARCH" in
  x86_64|amd64) ARCH="amd64" ;;
  aarch64|arm64) ARCH="arm64" ;;
  *)
    echo "Unsupported arch: ${ARCH}" >&2
    exit 1
    ;;
esac

# Release assets are versioned archives built by .goreleaser.yaml in the
# runner repo (saykai-runner_<version>_<os>_<arch>.<ext>), not a raw
# unversioned binary -- the archive is checksum-verified, then extracted to
# DEST_PATH below.
ASSET_SUFFIX="_${OS}_${ARCH}.${EXT}"
CHECKSUMS_NAME="checksums.txt"

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

mkdir -p "$(dirname "$DEST_PATH")"

download_from_base_url() {
  local base="$1"
  local version="$2"
  local asset_name="saykai-runner_${version}_${OS}_${ARCH}.${EXT}"

  echo "Downloading runner from base URL: ${base%/}/${version}/${asset_name}"
  curl -fsSL "${base%/}/${version}/${asset_name}" -o "${WORK_DIR}/${asset_name}"

  if ! curl -fsSL "${base%/}/${version}/${CHECKSUMS_NAME}" -o "${WORK_DIR}/${CHECKSUMS_NAME}"; then
    echo "WARNING: could not fetch ${CHECKSUMS_NAME} from base URL; skipping checksum verification." >&2
  fi

  echo "$asset_name" > "${WORK_DIR}/.asset_name"
}

github_api_get() {
  local url="$1"
  local token="$2"
  local out="$3"

  local code
  code="$(curl -sS -L -o "$out" -w "%{http_code}" \
    -H "Authorization: Bearer ${token}" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "$url")"

  if [[ "$code" -lt 200 || "$code" -ge 300 ]]; then
    echo "ERROR: GitHub API request failed (${code}) for ${url}" >&2
    echo "Response (first 300 chars):" >&2
    head -c 300 "$out" >&2 || true
    echo >&2
    exit 1
  fi
}

download_github_asset_by_id() {
  local repo="$1"
  local token="$2"
  local asset_id="$3"
  local dest="$4"

  curl -fsSL \
    -H "Authorization: Bearer ${token}" \
    -H "Accept: application/octet-stream" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "https://api.github.com/repos/${repo}/releases/assets/${asset_id}" -o "$dest"
}

download_from_github_release() {
  local repo="$1"
  local version="$2"
  local token="${SAYKAI_RUNNER_TOKEN:-}"

  if [[ -z "$token" ]]; then
    echo "Missing SAYKAI_RUNNER_TOKEN. For private GitHub releases you must provide a token with read access to ${repo}." >&2
    echo "Pass it as action input github-token: \${{ secrets.GITHUB_TOKEN }} (or a token with cross-repo access if runner-repo is a different, private repo)." >&2
    exit 1
  fi

  local api_base="https://api.github.com/repos/${repo}/releases"
  local release_url
  if [[ "$version" == "latest" ]]; then
    echo "Resolving latest release for ${repo}..."
    release_url="${api_base}/latest"
  else
    echo "Resolving release tag ${version} for ${repo}..."
    release_url="${api_base}/tags/${version}"
  fi

  local release_json="${WORK_DIR}/release.json"
  github_api_get "$release_url" "$token" "$release_json"

  # Match by SUFFIX, not exact name -- the version is embedded in the asset
  # filename (saykai-runner_<version>_<os>_<arch>.<ext>), so an exact name
  # can't be known ahead of time when runner_version=latest.
  local asset_name asset_id
  read -r asset_name asset_id < <(python3 -c '
import json, sys
suffix = sys.argv[1]
data = json.load(open(sys.argv[2]))
for a in data.get("assets", []):
    n = a.get("name", "")
    if n.endswith(suffix):
        print(n, a.get("id"))
        raise SystemExit(0)
raise SystemExit(1)
' "$ASSET_SUFFIX" "$release_json") || {
    echo "ERROR: No asset ending in '${ASSET_SUFFIX}' found in release ${version} for ${repo}" >&2
    echo "Available assets:" >&2
    python3 -c '
import json, sys
data = json.load(open(sys.argv[1]))
for a in data.get("assets", []):
    n = a.get("name")
    if n:
        print(n)
' "$release_json" >&2 || true
    exit 1
  }

  echo "Downloading runner asset '\''${asset_name}'\'' from GitHub (asset id: ${asset_id})..."
  download_github_asset_by_id "$repo" "$token" "$asset_id" "${WORK_DIR}/${asset_name}"

  # Best-effort checksums.txt fetch (also a release asset, matched by exact name).
  local checksums_id
  checksums_id="$(python3 -c '
import json, sys
data = json.load(open(sys.argv[1]))
for a in data.get("assets", []):
    if a.get("name") == "checksums.txt":
        print(a.get("id"))
        raise SystemExit(0)
raise SystemExit(1)
' "$release_json" 2>/dev/null)" || true

  if [[ -n "${checksums_id:-}" ]]; then
    download_github_asset_by_id "$repo" "$token" "$checksums_id" "${WORK_DIR}/${CHECKSUMS_NAME}"
  else
    echo "WARNING: no checksums.txt asset found on this release; skipping checksum verification." >&2
  fi

  echo "$asset_name" > "${WORK_DIR}/.asset_name"
}

verify_checksum() {
  local asset_name="$1"

  if [[ ! -f "${WORK_DIR}/${CHECKSUMS_NAME}" ]]; then
    return 0
  fi

  local expected
  expected="$(grep " ${asset_name}\$" "${WORK_DIR}/${CHECKSUMS_NAME}" | awk '{print $1}')"
  if [[ -z "$expected" ]]; then
    echo "WARNING: no checksum entry for ${asset_name} in ${CHECKSUMS_NAME}; skipping verification." >&2
    return 0
  fi

  local actual
  actual="$(sha256sum "${WORK_DIR}/${asset_name}" | awk '{print $1}')"
  if [[ "$expected" != "$actual" ]]; then
    echo "ERROR: checksum mismatch for ${asset_name}: expected ${expected}, got ${actual}" >&2
    exit 1
  fi
  echo "Checksum verified for ${asset_name}."
}

extract_and_install() {
  local asset_name="$1"
  local archive="${WORK_DIR}/${asset_name}"

  if [[ ! -s "$archive" ]]; then
    echo "ERROR: Runner archive not downloaded to ${archive}" >&2
    exit 1
  fi

  case "$EXT" in
    tar.gz) tar -xzf "$archive" -C "$WORK_DIR" "$BIN_NAME" ;;
    zip) unzip -o -q "$archive" "$BIN_NAME" -d "$WORK_DIR" ;;
  esac

  if [[ ! -s "${WORK_DIR}/${BIN_NAME}" ]]; then
    echo "ERROR: ${BIN_NAME} not found inside ${asset_name} after extraction." >&2
    exit 1
  fi

  mv "${WORK_DIR}/${BIN_NAME}" "$DEST_PATH"
}

validate_download() {
  if [[ ! -s "$DEST_PATH" ]]; then
    echo "ERROR: Runner not installed at ${DEST_PATH}" >&2
    exit 1
  fi

  # Catch common failure modes (HTML login page, JSON error, etc.) that slip
  # past a successful-looking curl if auth silently failed upstream.
  if command -v file >/dev/null 2>&1; then
    local ft
    ft="$(file -b "$DEST_PATH" || true)"
    echo "Runner file type: ${ft}"
    if [[ "$ft" == *"HTML"* || "$ft" == *"JSON"* || "$ft" == *"ASCII text"* ]]; then
      echo "ERROR: Installed runner does not look like a binary. Check token permissions and the release asset name." >&2
      exit 1
    fi
  fi
}

if [[ -n "$RUNNER_BASE_URL" ]]; then
  # Base URL mode expects: /<version>/<asset>
  if [[ "$RUNNER_VERSION" == "latest" ]]; then
    echo "runner_base_url provided but runner_version=latest is not supported for base URL mode." >&2
    echo "Use an explicit version tag like v1.0.1" >&2
    exit 1
  fi
  download_from_base_url "$RUNNER_BASE_URL" "$RUNNER_VERSION"
else
  download_from_github_release "$RUNNER_REPO" "$RUNNER_VERSION"
fi

ASSET_NAME="$(cat "${WORK_DIR}/.asset_name")"
verify_checksum "$ASSET_NAME"
extract_and_install "$ASSET_NAME"

chmod +x "$DEST_PATH"
validate_download
echo "Runner installed at: $DEST_PATH"
