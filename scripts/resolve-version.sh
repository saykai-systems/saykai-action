#!/usr/bin/env bash
set -euo pipefail

# Resolves runner-version to a concrete tag, so action.yml has something
# stable to key a cache on before deciding whether install-runner.sh needs
# to run at all. "latest" isn't cacheable on its own -- it means a
# different thing every release, so it has to become a real tag first.
#
# Only used ahead of the cache step; install-runner.sh keeps its own
# independent "latest" resolution too (unchanged) so it still works
# correctly if ever invoked directly/standalone, without depending on this
# script having run first.

RUNNER_REPO="${1:?RUNNER_REPO required (ex: saykai-systems/runner)}"
RUNNER_VERSION="${2:?RUNNER_VERSION required (ex: v1.0.1 or latest)}"

if [[ "$RUNNER_VERSION" != "latest" ]]; then
  echo "$RUNNER_VERSION"
  exit 0
fi

TOKEN="${SAYKAI_RUNNER_TOKEN:-}"
if [[ -z "$TOKEN" ]]; then
  echo "Missing SAYKAI_RUNNER_TOKEN; cannot resolve 'latest'." >&2
  exit 1
fi

RESPONSE_FILE="$(mktemp)"
trap 'rm -f "$RESPONSE_FILE"' EXIT

CODE="$(curl -sS -L -o "$RESPONSE_FILE" -w "%{http_code}" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  "https://api.github.com/repos/${RUNNER_REPO}/releases/latest")"

if [[ "$CODE" -lt 200 || "$CODE" -ge 300 ]]; then
  echo "ERROR: could not resolve latest release for ${RUNNER_REPO} (HTTP ${CODE})" >&2
  exit 1
fi

TAG="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("tag_name",""))' "$RESPONSE_FILE")"
if [[ -z "$TAG" ]]; then
  echo "ERROR: release response had no tag_name for ${RUNNER_REPO}" >&2
  exit 1
fi

echo "$TAG"
