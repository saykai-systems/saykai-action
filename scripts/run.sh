#!/usr/bin/env bash
set -euo pipefail

RUNNER_REPO="${1:-saykai-systems/runner}"
RUNNER_VERSION="${2:-latest}"
RUNNER_BASE_URL="${3:-}"
SPEC_PATH="${4:-saykai.yml}"
REPO_TOKEN="${5:-}"

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

emit_annotations() {
  # Prints ::error::/::warning:: workflow commands directly to stdout (not
  # redirected anywhere) so the Actions runner parses them live and renders
  # them as inline annotations on the flagged file/line in the PR's "Files
  # changed" tab (when that file is part of the diff) and in the job's
  # Annotations list either way. Purely cosmetic, like write_step_summary --
  # must never be able to affect $RC, so it degrades silently on any error.
  if [[ ! -f "$RESULT_PATH" ]]; then
    return 0
  fi

  if ! command -v python3 >/dev/null 2>&1; then
    return 0
  fi

  python3 - "$RESULT_PATH" <<'PY'
import json, sys

path = sys.argv[1]
try:
    with open(path, "r", encoding="utf-8") as f:
        d = json.load(f)
except (OSError, json.JSONDecodeError):
    sys.exit(0)

findings = d.get("findings", []) or []


def esc_message(s):
    # Workflow command data (the part after the final ::) only needs %, CR,
    # LF escaped.
    return str(s).replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")


def esc_prop(s):
    # Property values (file=, line=, title=) additionally need : and ,
    # escaped, since those delimit properties.
    return esc_message(s).replace(":", "%3A").replace(",", "%2C")


for finding in findings:
    rule_id = finding.get("rule_id") or "SAYKAI_FINDING"
    action = finding.get("action") or ""
    file_path = finding.get("file") or ""
    explanation = finding.get("explanation") or ""
    remediation = finding.get("remediation") or ""
    math_evidence = finding.get("math_evidence") or {}
    line = math_evidence.get("line")

    message = explanation
    if remediation:
        message = f"{explanation} {remediation}"
    if not message:
        message = rule_id

    # Blocking findings are errors; everything else (e.g. action: review) is
    # a warning -- tied to whether it actually gates the build, which is
    # more meaningful here than the raw severity label.
    level = "error" if action == "block" else "warning"

    props = [f"title={esc_prop(rule_id)}"]
    if file_path:
        props.append(f"file={esc_prop(file_path)}")
    if line:
        props.append(f"line={esc_prop(line)}")

    print(f"::{level} {','.join(props)}::{esc_message(message)}")
PY
}

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
# emit_annotations, write_step_summary, and the PR comment below are purely
# cosmetic reporting; `|| true` guarantees none of them can override $RC
# below, even via a failure mode not handled inside them (the JSON-parsing
# case is handled explicitly in each, but this is the backstop against
# anything else going wrong).
emit_annotations || true
write_step_summary "$RC" || true

# PR number only exists on pull_request(_target) events; GITHUB_EVENT_PATH
# is a JSON file GitHub always provides describing the trigger event.
PR_NUMBER=""
if [[ "${GITHUB_EVENT_NAME:-}" == "pull_request" || "${GITHUB_EVENT_NAME:-}" == "pull_request_target" ]]; then
  if [[ -n "${GITHUB_EVENT_PATH:-}" && -f "${GITHUB_EVENT_PATH}" ]] && command -v python3 >/dev/null 2>&1; then
    PR_NUMBER="$(python3 -c "
import json
try:
    with open('${GITHUB_EVENT_PATH}') as f:
        d = json.load(f)
    print(d.get('pull_request', {}).get('number', ''))
except (OSError, json.JSONDecodeError):
    pass
" 2>/dev/null || true)"
  fi
fi
bash "${ACTION_DIR}/pr-comment.sh" "$RESULT_PATH" "$REPO_TOKEN" "$PR_NUMBER" || true

# Preserve runner exit code
exit "$RC"
