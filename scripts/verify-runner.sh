#!/usr/bin/env bash
set -euo pipefail

RUNNER_PATH="$1"

if [[ ! -x "$RUNNER_PATH" ]]; then
  echo "Runner not executable: $RUNNER_PATH"
  exit 1
fi

# Basic sanity: print version if supported (saykai-runner has a `version`
# subcommand, not a --version flag).
if "$RUNNER_PATH" version >/dev/null 2>&1; then
  echo "Runner version: $("$RUNNER_PATH" version)"
else
  echo "Runner installed (no version subcommand supported)."
fi
