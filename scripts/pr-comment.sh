#!/usr/bin/env bash
set -euo pipefail

# Posts (or updates, in place) a single PR comment summarizing the run,
# using a hidden HTML marker to find and edit the same comment on every
# push instead of spamming a new one each time -- the standard pattern used
# by tools like Codecov/Danger/terraform-plan bots.
#
# Best-effort and silent: skips cleanly when this isn't a pull_request(-
# target) event, when REPO_TOKEN/PR_NUMBER/GITHUB_REPOSITORY aren't
# available, or on any API error. This is a reporting nicety -- like
# emit_annotations and write_step_summary in run.sh, it must never be able
# to affect the gate's real pass/fail exit code, so run.sh calls this with
# `|| true`.

RESULT_PATH="${1:?RESULT_PATH required}"
REPO_TOKEN="${2:-}"
PR_NUMBER="${3:-}"

MARKER="<!-- saykai-safety-gate -->"

if [[ -z "$REPO_TOKEN" ]]; then
  echo "Skipping PR comment (repo-token not provided)."
  exit 0
fi

if [[ -z "$PR_NUMBER" ]]; then
  echo "Skipping PR comment (not a pull_request event, or no PR number found)."
  exit 0
fi

if [[ -z "${GITHUB_REPOSITORY:-}" ]]; then
  echo "Skipping PR comment (GITHUB_REPOSITORY not set)."
  exit 0
fi

if [[ ! -f "$RESULT_PATH" ]]; then
  echo "Skipping PR comment ($RESULT_PATH not found)."
  exit 0
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "Skipping PR comment (python3 unavailable)."
  exit 0
fi

python3 - "$RESULT_PATH" "$MARKER" "$GITHUB_REPOSITORY" "$PR_NUMBER" "$REPO_TOKEN" <<'PY'
import json
import sys
import urllib.error
import urllib.request

result_path, marker, repo, pr_number, token = sys.argv[1:6]

try:
    with open(result_path, "r", encoding="utf-8") as f:
        d = json.load(f)
except (OSError, json.JSONDecodeError) as e:
    d = None
    parse_error = str(e)

if d is None:
    body_lines = [marker, "### Saykai Safety Gate", "", f"_Could not parse {result_path}: {parse_error}_"]
else:
    outcome = d.get("outcome", "UNKNOWN")
    trace_id = d.get("trace_id", "?")
    seal = d.get("seal", "")
    robot_class = d.get("robot_class", "")
    summary = d.get("summary", {}) or {}
    findings = d.get("findings", []) or []

    def format_evidence(me):
        if not me:
            return "n/a"
        method = me.get("method", "")
        if method == "threshold_comparison":
            observed, limit, op = me.get("observed"), me.get("limit"), me.get("operator", "")
            op_symbol = {"gt": ">", "lt": "<"}.get(op, op)
            if observed is not None and limit is not None:
                return f"{observed:.4f} {op_symbol} {limit:.4f}"
        elif method == "shannon_entropy":
            score, threshold = me.get("score"), me.get("threshold")
            if score is not None and threshold is not None:
                return f"score {score:.2f} > {threshold:.2f}"
        return "n/a"

    icon = {"PASS": ":white_check_mark:", "BLOCK": ":no_entry:"}.get(outcome, ":warning:")

    body_lines = [marker, f"### {icon} Saykai Safety Gate: {outcome}", ""]
    seal_part = f" | **Seal:** `{seal[:12]}...`" if seal else ""
    class_part = f" | **Robot class:** {robot_class}" if robot_class else ""
    body_lines.append(f"**Trace ID:** `{trace_id}`{seal_part}{class_part}")
    body_lines.append(
        f"**Files scanned:** {summary.get('files_scanned', '?')} | "
        f"**Findings:** {summary.get('findings_count', '?')} | "
        f"**Blocking:** {summary.get('blocking_findings', '?')}"
    )

    if findings:
        body_lines.append("")
        body_lines.append("| Rule | Severity | Action | File | Evidence |")
        body_lines.append("| --- | --- | --- | --- | --- |")
        for finding in findings:
            evidence = format_evidence(finding.get("math_evidence") or {})
            body_lines.append(
                f"| `{finding.get('rule_id', '')}` | {finding.get('severity', '')} | "
                f"{finding.get('action', '')} | `{finding.get('file', '')}` | {evidence} |"
            )
        body_lines.append("")
        body_lines.append(
            "_Remediation guidance, allowlist status, and the signed evidence "
            "artifact are in this run's job summary and Artifacts._"
        )

body = "\n".join(body_lines)


def api_request(url, method="GET", data=None):
    req = urllib.request.Request(url, method=method)
    req.add_header("Authorization", f"Bearer {token}")
    req.add_header("Accept", "application/vnd.github+json")
    req.add_header("X-GitHub-Api-Version", "2022-11-28")
    if data is not None:
        req.data = json.dumps(data).encode("utf-8")
        req.add_header("Content-Type", "application/json")
    with urllib.request.urlopen(req) as resp:
        return json.loads(resp.read().decode("utf-8"))


comments_url = f"https://api.github.com/repos/{repo}/issues/{pr_number}/comments"

try:
    existing_id = None
    page = 1
    while True:
        comments = api_request(f"{comments_url}?per_page=100&page={page}")
        if not comments:
            break
        match = next((c for c in comments if marker in (c.get("body") or "")), None)
        if match:
            existing_id = match["id"]
            break
        if len(comments) < 100:
            break
        page += 1

    if existing_id:
        api_request(
            f"https://api.github.com/repos/{repo}/issues/comments/{existing_id}",
            method="PATCH",
            data={"body": body},
        )
        print(f"Updated existing PR comment ({existing_id}).")
    else:
        api_request(comments_url, method="POST", data={"body": body})
        print("Posted new PR comment.")
except urllib.error.HTTPError as e:
    print(f"Could not post/update PR comment: HTTP {e.code} {e.reason}")
except OSError as e:
    print(f"Could not post/update PR comment: {e}")
PY
