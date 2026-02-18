# Saykai Safety Gate

**CI enforcement for AI systems.**

Saykai evaluates AI changes during pull requests and blocks unsafe regressions before they ship. It converts Safety Spec evaluations into deterministic CI outcomes, ensuring that your AI agents and models remain reliable as they evolve.

---

## Overview

The Saykai Safety Gate integrates directly with GitHub Actions to enforce AI safety policies as code. Instead of relying on manual spot-checks or non-deterministic monitoring, Saykai treats safety as a testable contract.

On every pull request, this action:
* **Evaluates** changes against a defined Safety Spec.
* **Detects** safety regressions introduced by prompt, tool, or configuration changes.
* **Fails** the build when high-severity violations are found.
* **Produces** clear, actionable summaries inside the Pull Request.

The result is a single, unambiguous CI status: **pass**, **block**, or **report-only**.

## Usage

Add the following step to your `.github/workflows/safety.yml` file:

```yaml
name: AI Safety Check
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
        uses: saykai/saykai-action@v1
        with:
          spec-path: 'saykai.yml'
          github-token: ${{ secrets.GITHUB_TOKEN }}

## Configuration

| Input | Description | Required | Default |
| :--- | :--- | :--- | :--- |
| `spec-path` | Path to your Saykai safety specification file. | No | `saykai.yml` |
| `github-token` | The GitHub token used to post safety summaries to the PR. | Yes | `${{ github.token }}` |
| `fail-on-error` | If `true`, the CI job fails if the Saykai engine encounters an internal error (Fail Closed). | No | `true` |

## How It Works

1.  **Trigger:** CI triggers the Saykai Safety Gate on a pull request.
2.  **Execution:** The gate invokes the Saykai evaluation engine with the appropriate context.
3.  **Analysis:** Evaluation results are interpreted deterministically against your policy.
4.  **Reporting:** The pull request receives a CI status reflecting policy compliance.

> **Reliability Guarantee:** If evaluation results are missing, invalid, or ambiguous, the gate **fails closed**.

## Enforcement Model

Saykai treats safety as a testable contract to ensure behavior does not regress silently over time.

* **Policies as Code:** Safety policies are defined strictly in code.
* **Repeatability:** Evaluations are repeatable and deterministic.
* **Clear Violations:** Violations are surfaced with rule identifiers and remediation guidance.
* **Configurable Thresholds:** Enforcement thresholds can be configured per repository or environment.

## Design Principles

* **Deterministic CI outcomes:** No "flaky" safety tests.
* **Clear and actionable failure messages:** Developers receive specific rule violations, not vague warnings.
* **Safety-first defaults:** The system assumes "unsafe" until proven "compliant."
* **Explicit, versioned interfaces:** Policies are code, version-controlled alongside your application.

## Data Handling

Saykai is designed for enterprise security and privacy requirements.

* **Ephemeral:** Prompts and raw outputs are not retained by the action.
* **Minimal Surface:** Only evaluation results (pass/fail signals) and rule identifiers are surfaced to CI.
* **Sanitized Logs:** Console logs are concise and scrubbed of sensitive data by default.
* **Configurable:** Retention and evidence options can be configured as needed.

## Scope

This repository provides the CI-facing enforcement layer. It is responsible for:

* Input validation and normalization.
* Invoking the Saykai evaluation engine.
* Converting evaluation results into CI signals.
* Failing closed when required.

*Core evaluation logic, policy definitions, and scoring mechanisms are maintained separately.*

## License

[MIT](LICENSE) © 2026 Saykai
