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
          github-token: ${{ secrets.GITHUB_TOKEN }}
```

## Configuration

| Input             | Description                                                                            | Required | Default                    |
| :----------------- | :--------------------------------------------------------------------------------------- | :------- | :--------------------------- |
| `spec-path`       | Path to your Saykai project spec (`saykai.yml`).                                        | No       | `saykai.yml`               |
| `github-token`    | Token with read access to the runner release repo (`runner-repo`).                      | Yes      | —                          |
| `runner-repo`     | Repo that hosts the `saykai-runner` release assets (`owner/name`).                       | No       | `saykai-systems/runner`    |
| `runner-version`  | `saykai-runner` release tag (e.g. `v1.0.1`) or `latest`.                                 | No       | `latest`                   |
| `runner-base-url` | Alternate download base for a self-hosted mirror (e.g. `https://downloads.saykai.com/runner`). Requires an explicit `runner-version` — not compatible with `latest`. | No       | _(unset — uses `runner-repo`)_ |
| `fail-on-error`   | If `true`, the CI job fails if the Saykai engine encounters an internal error (Fail Closed). | No       | `true`                     |

## How It Works

1.  **Trigger:** CI triggers the Saykai Safety Gate on a pull request.
2.  **Install:** The action downloads and checksum-verifies the matching
    `saykai-runner` release for the job's OS/architecture.
3.  **Execution:** The gate invokes `saykai-runner run` against your Nav2
    config and safety policy.
4.  **Analysis:** Findings are interpreted deterministically against your
    policy's thresholds and rules.
5.  **Reporting:** The pull request receives a CI status reflecting policy
    compliance, plus a findings table in the job summary.

> **Reliability Guarantee:** If evaluation results are missing, invalid, or
> ambiguous, the gate **fails closed**.

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

Saykai is designed for enterprise security and privacy requirements.

* **Minimal Surface:** Only evaluation results (findings, pass/block signal)
  are surfaced to CI — not your robot's raw sensor data or telemetry.
* **Sanitized Logs:** Console logs are concise and scrubbed of sensitive
  data by default.
* **Configurable:** Retention and evidence options can be configured as
  needed on the runner side (see `saykai-runner`'s audit trail and
  signature verification).

## Scope

This repository provides the CI-facing enforcement layer. It is
responsible for:

* Downloading and checksum-verifying the `saykai-runner` binary.
* Invoking the Saykai evaluation engine (`saykai-runner run`).
* Converting evaluation results into CI signals and a job summary.
* Failing closed when required.

*Core evaluation logic, policy definitions, and scoring mechanisms are
maintained separately, in the (private) `saykai-systems/runner` repo.*

## License

[MIT](LICENSE) © 2026 Saykai
