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

# Derived independently (not inherited from run.sh's own export) so this
# script's python3 heredoc can `import evidence` (scripts/evidence.py)
# whether it's invoked from run.sh or run standalone.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export PYTHONPATH="${SCRIPT_DIR}${PYTHONPATH:+:${PYTHONPATH}}"

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
from evidence import format_evidence

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
        raw = resp.read().decode("utf-8")
        # DELETE (and some other calls) return 204 No Content -- no body to
        # parse. Every existing caller (GET/POST/PATCH here) always expects
        # real JSON back, so this only changes behavior for the new DELETE
        # calls below.
        return json.loads(raw) if raw else None


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
        created = api_request(comments_url, method="POST", data={"body": body})
        created_id = created.get("id") if created else None
        print(f"Posted new PR comment ({created_id}).")

        # Guards against a real race: this is a plain read-then-write (GET
        # to check for an existing marker comment, then POST/PATCH based on
        # what that GET saw), so two overlapping runs on the same PR (a
        # fast double-push, a manual re-run overlapping a new push) can
        # both GET before either has POSTed, both find nothing, and both
        # POST -- producing duplicate comments instead of the single-
        # comment guarantee described at the top of this file. This script
        # can't ask the calling workflow for a concurrency: group (that's
        # the customer's own workflow, not this repo's), so the fix has to
        # live here: re-check right after our own POST and delete any
        # other marker comment that shows up, keeping the one we just
        # created. If both racing runs do this, each may find the other's
        # comment already 404'd on delete -- caught below and ignored,
        # either way exactly one comment survives.
        if created_id is not None:
            page = 1
            while True:
                comments = api_request(f"{comments_url}?per_page=100&page={page}")
                if not comments:
                    break
                for c in comments:
                    cid = c.get("id")
                    if cid != created_id and marker in (c.get("body") or ""):
                        try:
                            api_request(
                                f"https://api.github.com/repos/{repo}/issues/comments/{cid}",
                                method="DELETE",
                            )
                            print(f"Removed a duplicate PR comment ({cid}) from a race with another run.")
                        except (urllib.error.HTTPError, OSError):
                            pass
                if len(comments) < 100:
                    break
                page += 1
except urllib.error.HTTPError as e:
    print(f"Could not post/update PR comment: HTTP {e.code} {e.reason}")
except OSError as e:
    print(f"Could not post/update PR comment: {e}")
PY
