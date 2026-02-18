# Saykai Safety Gate

CI enforcement for AI systems.

Saykai evaluates AI changes during pull requests and blocks unsafe regressions before they ship. It converts Safety Spec evaluations into deterministic CI outcomes.

---

## Overview

The Saykai Safety Gate integrates directly with CI to enforce AI safety policies as code.

On every pull request, it:

- Evaluates changes against a defined Safety Spec
- Detects safety regressions introduced by prompt, tool, or configuration changes
- Fails the build when high-severity violations are found
- Produces clear, actionable summaries inside GitHub

The result is a single, unambiguous CI status: pass, block, or report-only.

---

## How It Works

1. CI triggers the Saykai Safety Gate.
2. The gate invokes the Saykai evaluation engine with the appropriate context.
3. Evaluation results are interpreted deterministically.
4. The pull request receives a CI status reflecting policy compliance.

If evaluation results are missing, invalid, or ambiguous, the gate fails closed.

---

## Enforcement Model

Saykai treats safety as a testable contract.

- Safety policies are defined as code.
- Evaluations are repeatable and deterministic.
- Violations are surfaced with rule identifiers and remediation guidance.
- Enforcement thresholds can be configured per repository or environment.

This ensures that safety behavior does not regress silently over time.

---

## Design Principles

- Deterministic CI outcomes  
- Clear and actionable failure messages  
- No nondeterministic or flaky behavior  
- Safety-first defaults  
- Explicit, versioned interfaces  

---

## Data Handling

By default:

- Prompts are not stored
- Outputs are not retained
- Only evaluation results and rule identifiers are surfaced to CI

Logs are concise and scrubbed of sensitive data.  
Retention and evidence options can be configured as needed.

---

## Scope

This repository provides the CI-facing enforcement layer.

It is responsible for:

- Input validation and normalization
- Invoking the Saykai evaluation engine
- Converting evaluation results into CI signals
- Failing closed when required

Core evaluation logic, policy definitions, and scoring mechanisms are maintained separately.

---

## Usage

Add the Safety Gate to your GitHub workflow:

```yaml
- uses: saykai/saykai-action@v1
  with:
    spec-path: safety/safety-spec.yml
