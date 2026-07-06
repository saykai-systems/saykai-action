#!/usr/bin/env bash
set -euo pipefail

RUNNER_REPO="${1:-saykai-systems/runner}"
RUNNER_VERSION="${2:-latest}"
RUNNER_BASE_URL="${3:-}"
SPEC_PATH="${4:-saykai.yml}"

ACTION_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${GITHUB_WORKSPACE:-$(pwd)}"
BIN_DIR="${WORK_DIR}/.saykai/bin"
RUNNER_PATH="${BIN_DIR}/saykai-runner"

# The runner writes its own fixed output paths (outputs/run-result.json,
# safety_pack.json) relative to its working directory -- it has no --out
# flag to redirect them, so RESULT_PATH must match that fixed location,
# not a user-configurable one.
RESULT_PATH="outputs/run-result.json"

mkdir -p "$BIN_DIR"

# Run from the workspace so relative paths (spec/policy/scan root) behave predictably
cd "$WORK_DIR"

# Install runner
bash "${ACTION_DIR}/install-runner.sh" \
  "$RUNNER_REPO" \
  "$RUNNER_VERSION" \
  "$RUNNER_BASE_URL" \
  "$RUNNER_PATH"

# Optional verification (safe to keep even if you don't have checksums yet)
bash "${ACTION_DIR}/verify-runner.sh" "$RUNNER_PATH" || true

write_step_summary() {
  local rc="$1"

  # If GitHub step summary isn't available, do nothing
  if [[ -z "${GITHUB_STEP_SUMMARY:-}" ]]; then
    return 0
  fi

  {
    echo "## Saykai Safety Gate"
    echo ""
    echo "**Exit code:** ${rc}"
    echo "**Spec:** \`${SPEC_PATH}\`"
    echo "**Result:** \`${RESULT_PATH}\`"
    echo ""
  } >> "$GITHUB_STEP_SUMMARY"

  if [[ -f "$RESULT_PATH" ]]; then
    if command -v python3 >/dev/null 2>&1; then
      python3 - "$RESULT_PATH" >> "$GITHUB_STEP_SUMMARY" <<'PY'
import json, sys

path = sys.argv[1]
try:
    with open(path, "r", encoding="utf-8") as f:
        d = json.load(f)
except (OSError, json.JSONDecodeError) as e:
    # The step summary is informational only -- it must never be able to
    # affect the action's real pass/fail exit code (that's $RC, captured
    # separately in run.sh from the runner's own process, not from this
    # script). Degrade gracefully instead of raising: a crashed/truncated
    # run-result.json would otherwise make this process exit non-zero,
    # which -- because this call happens after `set -e` is re-enabled in
    # run.sh -- would replace the runner's real exit code with this
    # script's, silently corrupting the CI gate's own verdict.
    print(f"_Could not parse {path}: {e}_")
    print("")
    sys.exit(0)

outcome = d.get("outcome", "UNKNOWN")
trace_id = d.get("trace_id", "?")
seal = d.get("seal", "")
summary = d.get("summary", {}) or {}
findings = d.get("findings", []) or []

print(f"**Outcome:** {outcome}")
print(f"**Trace ID:** {trace_id}")
if seal:
    print(f"**Seal:** {seal[:12]}...")

print(
    f"**Files scanned:** {summary.get('files_scanned', '?')} | "
    f"**Findings:** {summary.get('findings_count', '?')} | "
    f"**Blocking:** {summary.get('blocking_findings', '?')}"
)

if findings:
    print("")
    print("### Findings")
    print("")
    print("| Rule | Severity | Action | File |")
    print("| --- | --- | --- | --- |")
    for finding in findings:
        rule_id = finding.get("rule_id", "")
        severity = finding.get("severity", "")
        action = finding.get("action", "")
        file_path = finding.get("file", "")
        print(f"| `{rule_id}` | {severity} | {action} | `{file_path}` |")
PY
    else
      {
        echo "_${RESULT_PATH} exists but python3 is unavailable to render a summary._"
        echo ""
      } >> "$GITHUB_STEP_SUMMARY"
    fi
  else
    {
      echo "_No run-result.json found at the expected path. Runner may have failed before writing output._"
      echo ""
    } >> "$GITHUB_STEP_SUMMARY"
  fi
}

# Run (capture exit code so we can always write a summary)
echo "Running Saykai runner..."
set +e
"$RUNNER_PATH" run --spec "$SPEC_PATH"
RC=$?
set -e

echo "Saykai completed. Result: $RESULT_PATH"
# write_step_summary is purely cosmetic reporting; `|| true` guarantees it
# can never override $RC below, even via a failure mode not handled inside
# it (the JSON-parsing case is handled explicitly above, but this is the
# backstop against anything else going wrong in there).
write_step_summary "$RC" || true

# Preserve runner exit code
exit "$RC"
