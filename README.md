# Saykai Safety Gate

**CI enforcement for robot navigation configs.**

Saykai audits Nav2/ROS2 robot configuration changes during pull requests
and blocks unsafe regressions before they ship — velocity limits,
acceleration limits, safety-bubble/inflation radius, and cross-parameter
risks like stopping distance and footprint clearance.

---

## Overview

The Saykai Safety Gate integrates directly with GitHub Actions to enforce
robot safety policies as code. Instead of relying on manual spot-checks or
non-deterministic review, Saykai treats safety as a testable contract
against a customer-approved policy.

On every pull request, this action:
* **Evaluates** Nav2/ROS2 config changes against a defined safety policy.
* **Detects** threshold and cross-parameter safety regressions introduced
  by config changes (e.g. a velocity or acceleration limit increase, an
  inflation radius shrinking below the robot's own footprint).
* **Fails** the build when high-severity violations are found.
* **Produces** clear, actionable summaries inside the Pull Request.

The result is a single, unambiguous CI status: **pass**, **block**, or
**report-only**.

## Usage

Add the following step to your `.github/workflows/safety.yml` file:

```yaml
name: Robot Safety Check
on: [pull_request]

permissions:
  contents: read
  pull-requests: write

jobs:
  saykai-check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Run Saykai Safety Gate
        uses: saykai-systems/saykai-action@v1
        with:
          spec-path: 'saykai.yml'
          # Provided by Saykai as part of onboarding -- scoped to read only
          # the saykai-releases repo, never Saykai's source. This is NOT
          # the auto-generated ${{ secrets.GITHUB_TOKEN }}, which only has
          # access to your own repo and can't read saykai-releases at all.
          github-token: ${{ secrets.SAYKAI_RELEASES_TOKEN }}
          # Optional: posts/updates a single PR comment summarizing the run.
          # This IS the auto-generated token -- it's scoped to your own
          # repo, which is exactly what's needed to comment on your own PR.
          repo-token: ${{ secrets.GITHUB_TOKEN }}
```

Don't have a `saykai.yml`/`saykai-policy.yml` yet? See
[`quickstart/`](quickstart/) for a real, working starting pair you can
copy into your own repo — not illustrative pseudo-config, an actual policy
file that's been run and verified.

## Configuration

| Input             | Description                                                                            | Required | Default                    |
| :----------------- | :--------------------------------------------------------------------------------------- | :------- | :--------------------------- |
| `spec-path`       | Path to your Saykai project spec (`saykai.yml`).                                        | No       | `saykai.yml`               |
| `github-token`    | Token with read access to `runner-repo`. Should be scoped to that repo only -- see Security below. | Yes      | —                          |
| `runner-repo`     | Repo that hosts the `saykai-runner` release assets (`owner/name`). A dedicated release-hosting repo containing only compiled binaries, not Saykai's source. | No       | `saykai-systems/saykai-releases` |
| `runner-version`  | `saykai-runner` release tag (e.g. `v1.0.1`) or `latest`.                                 | No       | `latest`                   |
| `runner-base-url` | Alternate download base for a self-hosted mirror (e.g. `https://downloads.saykai.com/runner`). Requires an explicit `runner-version` — not compatible with `latest`. | No       | _(unset — uses `runner-repo`)_ |
| `fail-on-error`   | If `true`, the CI job fails if the Saykai engine encounters an internal error (Fail Closed). | No       | `true`                     |
| `repo-token`      | Token with `pull-requests: write` on *your own* repo (not `runner-repo`) -- typically `${{ secrets.GITHUB_TOKEN }}`. When set, posts/updates a single PR comment summarizing the run (findings table included). Requires your workflow to grant `pull-requests: write`. | No | _(unset — no PR comment posted)_ |

## How It Works

1.  **Trigger:** CI triggers the Saykai Safety Gate on a pull request.
2.  **Install:** The action downloads and checksum-verifies the matching
    `saykai-runner` release for the job's OS/architecture. Verification is
    mandatory, not best-effort: if `checksums.txt` isn't available, or has
    no entry for the downloaded asset, the action **fails** rather than
    installing an unverified binary.
3.  **Execution:** The gate invokes `saykai-runner run` against your Nav2
    config and safety policy.
4.  **Analysis:** Findings are interpreted deterministically against your
    policy's thresholds and rules.
5.  **Reporting:** The pull request receives a CI status reflecting policy
    compliance, a findings table (with observed-vs-limit evidence, not just
    a rule ID) in the job summary, inline annotations on the flagged
    file/line (in "Files changed" and the job's Annotations list), and --
    if `repo-token` is set -- a single PR comment summarizing the run,
    updated in place on every push rather than posted fresh each time. The
    job summary also expands into full remediation guidance and allowlist
    status per finding.
6.  **Evidence:** The signed `safety_pack.json` for the run is uploaded as
    a workflow artifact (`saykai-safety-pack`, 90-day retention) on every
    run, pass or block -- a portable, downloadable record for audit or
    governance, not just a CI-only signal. See Verifying a Safety Pack
    below.

> **Reliability Guarantee:** If evaluation results are missing, invalid, or
> ambiguous, the gate **fails closed**. This extends to the binary itself:
> if its integrity can't be verified, installation fails closed too.

## Verifying a Safety Pack

Every run uploads its signed `safety_pack.json` as a workflow artifact,
regardless of outcome. Download it from the run's **Artifacts** section,
extract it, then from the same directory confirm it hasn't been altered
since it was sealed:

```
saykai-runner verify
```

(`verify` looks for `safety_pack.json` in the current directory by
default.) This checks the cryptographic seal (and, when the machine holds
the trusted signing key, the Ed25519 signature) over the *entire* record --
not just the findings, every field -- so an edited outcome, timestamp, or
finding is detected, not just a tampered file hash. This is what makes the
artifact something you can actually hand to an auditor or attach to a
change record, rather than a JSON file that's only trustworthy as long as
nobody's touched it.

## Enforcement Model

Saykai treats safety as a testable contract to ensure Nav2/ROS2
configuration does not regress silently over time.

* **Policies as Code:** Safety policies are defined strictly in code
  (`saykai-policy.yml`), version-controlled alongside your application.
* **Repeatability:** Evaluations are repeatable and deterministic.
* **Clear Violations:** Violations are surfaced with rule identifiers,
  math evidence (observed value vs. limit), and remediation guidance.
* **Configurable Thresholds:** Enforcement thresholds are configured per
  robot class (`class_a`/`class_b`/`class_c`) via the policy file.

## Design Principles

* **Deterministic CI outcomes:** No "flaky" safety tests.
* **Clear and actionable failure messages:** Developers receive specific
  rule violations, not vague warnings.
* **Safety-first defaults:** The system assumes "unsafe" until proven
  "compliant."
* **Explicit, versioned interfaces:** Policies are code, version-controlled
  alongside your application.

## Data Handling

**Your Nav2 config never leaves your own CI runner.** This isn't a policy
promise — it follows directly from how the system is built: Saykai has no
backend service this action talks to. The only network calls this action
ever makes are (1) downloading the `saykai-runner` binary from
`saykai-releases`, checksum-verified before use, and (2) — only if you set
`repo-token` — posting a comment back to your own pull request via
GitHub's own API. Your actual robot configuration is read, evaluated, and
reported on entirely inside the runner executing your workflow (GitHub-
hosted or self-hosted). It is never transmitted to Saykai, logged by
Saykai, or stored anywhere outside your own repository and CI environment.

* **No telemetry, no phone-home:** the `saykai-runner` binary itself makes
  no network calls during evaluation — it reads local files and writes
  local files, full stop.
* **Minimal surface in CI:** only evaluation results (findings, pass/block
  signal, a cryptographic seal) reach your PR — not raw sensor data,
  telemetry, or anything beyond what's already in your Nav2 config.
* **Audit trail stays yours:** signed audit records (`audits/*.json`,
  `safety_pack.json`) are written to your own workspace/job artifacts,
  under your own retention and access control — Saykai never receives a
  copy, automatically or otherwise.
* **Sanitized logs:** console output is concise and scrubbed of sensitive
  data by default.

## Security

`runner-repo` defaults to `saykai-systems/saykai-releases` — a dedicated,
private repo that holds nothing but compiled `saykai-runner` binaries and
their checksums. This is deliberate: GitHub's permission model has no scope
that means "read releases only" — a token with read access to a repo can
clone that repo's entire contents. Your `github-token` should be a
credential scoped to `saykai-releases` alone (a fine-grained PAT, ideally),
never one with any access to Saykai's actual source repo. If you're issued
a token, verify its scope is limited to `saykai-releases` before using it
here.

Downloaded binaries are checksum-verified against the release's
`checksums.txt` before being executed — this is mandatory, not best-effort
(see the Reliability Guarantee above).

## Scope

This repository provides the CI-facing enforcement layer. It is
responsible for:

* Downloading and checksum-verifying the `saykai-runner` binary.
* Invoking the Saykai evaluation engine (`saykai-runner run`).
* Converting evaluation results into CI signals and a job summary.
* Failing closed when required.

*Core evaluation logic, policy definitions, and scoring mechanisms are
maintained separately, in a private source repo that this action and its
release artifacts never expose.*

## License

[MIT](LICENSE) © 2026 Saykai
