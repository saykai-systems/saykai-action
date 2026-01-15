# saykai-ci-safety-gate

Internal CI safety gate for Saykai.

This repository contains the CI-facing integration layer that invokes Saykai evaluations and translates results into enforceable CI outcomes. It is private by design.

## Purpose
- Act as the enforcement boundary between CI systems and Saykai evaluations
- Invoke the Saykai runner in a controlled, repeatable way
- Convert evaluation results into CI signals (pass, block, report-only)
- Surface human-readable summaries and machine-readable outputs for downstream steps

## What this repo is NOT
- Not a public GitHub Action
- Not a general-purpose CI plugin
- Not a reference implementation for external users

## Responsibilities
This repo is responsible for:
- Input validation and normalization
- Calling the runner with the appropriate context
- Interpreting runner output deterministically
- Failing closed when results are missing, invalid, or ambiguous

This repo is explicitly **not** responsible for:
- Core evaluation logic
- Rule or policy definition
- Safety decision heuristics

Those live elsewhere.

## Expected behavior
When functioning correctly, this safety gate should:
- Produce a single, unambiguous CI result
- Make failures obvious and actionable
- Avoid flaky or non-deterministic behavior
- Default to safety over permissiveness

## Repo hygiene
- No secrets in git. Use CI-provided secrets only.
- Do not commit production specs, rules, or policies.
- Keep logs concise and scrubbed of sensitive data.
- Avoid adding demo or example workflows intended for public use.

## Change management
- Treat interface changes as breaking unless proven otherwise
- Update any dependent internal workflows when contracts change
- Prefer backward-compatible output whenever possible

## Ownership
Maintained by the Saykai team.
