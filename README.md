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
          github-token: ${{ secrets.SAYKAI_RELEASES_READ_TOKEN }}
          # Optional: posts/updates a single PR comment summarizing the run.
          # This IS the auto-generated token -- it's scoped to your own
          # repo, which is exactly what's needed to comment on your own PR.
          repo-token: ${{ secrets.GITHUB_TOKEN }}
          # Optional but recommended: signs the evidence with a key you hold,
          # so anyone can verify it later. See "Signing key" below.
          signing-key: ${{ secrets.SAYKAI_SIGNING_KEY }}
```

Store the token Saykai gives you as a repository secret named
`SAYKAI_RELEASES_READ_TOKEN` (the name is up to you; the examples here use
this one).

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
| `fail-on-error`   | If `true`, the job fails when the gate blocks a change or cannot complete (fail closed). If `false`, the job never fails: blocked changes are reported as warnings but **not stopped**. Use `false` only to trial the gate without enforcing it. | No       | `true`                     |
| `artifact-name`   | Name of the uploaded evidence artifact. Must be unique within a workflow run: set a different name for each invocation if the gate runs more than once (see [Running the gate more than once](#running-the-gate-more-than-once)). | No | `saykai-safety-pack` |
| `repo-token`      | Token with `pull-requests: write` on *your own* repo (not `runner-repo`) -- typically `${{ secrets.GITHUB_TOKEN }}`. When set, posts/updates a single PR comment summarizing the run (findings table included). Requires your workflow to grant `pull-requests: write`. | No | _(unset — no PR comment posted)_ |
| `signing-key`     | Your private signing key (the contents of `saykai-signing.key`, made once with `saykai-runner keygen`), passed as a secret. When set, every safety pack is signed with it so anyone with your public key can verify the evidence. Unset or empty (for example on pull requests from forks, which cannot read secrets): the run is signed with a temporary key that is discarded when the job ends. Needs `saykai-runner` v1.4.0 or newer; with an older runner the action stops rather than ignore the key. See [Signing key](#signing-key). | No | _(unset: temporary key)_ |

### Outputs

| Output              | Description |
| :------------------ | :---------- |
| `outcome`           | `PASS` or `BLOCK` from the gate, or `ERROR` if the gate could not produce a result. |
| `blocking-findings` | Number of findings that blocked the change (`0` on a pass). |
| `findings`          | Total number of findings, including non-blocking review findings. |
| `trace-id`          | Trace ID of the run, as recorded in the safety pack. |
| `signed-by-key`     | Key ID that signed the safety pack. With `signing-key` set, this is your persistent key. |
| `evidence-uploaded` | `true` if the signed safety pack was uploaded as an artifact. |

Outputs are set on a block too, so a later step can act on them. Give the
gate step an `id` and add `if: always()` to the later step:

```yaml
      - name: Run Saykai Safety Gate
        id: saykai
        uses: saykai-systems/saykai-action@v1
        with:
          github-token: ${{ secrets.SAYKAI_RELEASES_READ_TOKEN }}

      - name: Notify on a block
        if: always() && steps.saykai.outputs.outcome == 'BLOCK'
        run: echo "Blocked with ${{ steps.saykai.outputs.blocking-findings }} finding(s)"
```

### Running the gate more than once

GitHub requires artifact names to be unique within a workflow run. If the
gate runs more than once (a matrix, or one run per robot class), give each
run its own `artifact-name`, or only the first run's evidence is kept. If an
upload fails for this or any other reason, the job shows an "Evidence not
saved" warning and `evidence-uploaded` is `false`.

```yaml
    strategy:
      matrix:
        robot: [class_a, class_b]
    steps:
      - uses: actions/checkout@v4
      - uses: saykai-systems/saykai-action@v1
        with:
          spec-path: robots/${{ matrix.robot }}/saykai.yml
          github-token: ${{ secrets.SAYKAI_RELEASES_READ_TOKEN }}
          artifact-name: saykai-safety-pack-${{ matrix.robot }}
```

`runner-version` defaults to `latest`, so new runner releases (which can add
checks) reach your pipeline automatically. If you need runs to be exactly
reproducible, pin it to a release tag such as `v1.4.0`.

## What gets audited

The gate reads **every YAML file under your scan root** (`scan.root` in
`saykai.yml`), whatever the file is called: `nav2_params.yaml`,
`controller.yaml` and `robot_nav.yml` are all audited the same way. Hidden
folders (names starting with a dot, such as `.git` and `.github`),
`node_modules`, `__pycache__`, and the gate's own `outputs` and `audits`
folders are skipped, and so are files whose names start with `saykai` (the
gate's own `saykai.yml` and policy files).

If the gate finds **no Nav2 safety parameters at all** (no velocity,
acceleration, inflation radius or scaling setting in any YAML file) and no
behavioral scenarios ran, it **blocks** with `NO_NAV2_CONFIG_AUDITED` instead
of passing. A pass that checked nothing would say nothing about your robot.
The usual fix is to point `scan.root` at the folder that holds your Nav2
parameters. A repo that is deliberately gated some other way can set that
rule to `action: review` (or `enabled: false`) in its policy.

Every run states what it covered, so a pass can be read for what it is:

```
SCOPE: 1 file(s) scanned for secrets | 1 Nav2 file(s) audited, 9 safety parameter(s) checked
```

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
    a workflow artifact (`saykai-safety-pack` unless you set
    `artifact-name`, 90-day retention) on every run, pass or block -- a portable, downloadable record for audit or
    governance, not just a CI-only signal. See Verifying a Safety Pack
    below.

> **Reliability Guarantee:** If evaluation results are missing, invalid, or
> ambiguous, the gate **fails closed**. This extends to the binary itself:
> if its integrity can't be verified, installation fails closed too.

## Signing key

Every run produces a signed `safety_pack.json`. By default that signature
comes from a temporary key that exists only on the CI machine and is thrown
away when the job ends, so nobody who was not on that machine can ever check
the evidence. To make it checkable by your auditors, insurers or customers,
sign with a key you keep:

1. Create a key once, on your own machine (this prints no secret):

   ```
   saykai-runner keygen
   ```

   It writes `saykai-signing.pub` (the public half, safe to share) and
   `saykai-signing.key` (the private half). It never overwrites an existing
   key.
2. Store the private half as a repository secret named `SAYKAI_SIGNING_KEY`,
   then delete the file from your machine:

   ```
   cat saykai-signing.key | gh secret set SAYKAI_SIGNING_KEY
   ```

3. Commit `saykai-signing.pub` to your repo. Anyone can use it to verify your
   evidence; it cannot be used to sign anything.
4. Pass the secret to the action, as in the Usage example:
   `signing-key: ${{ secrets.SAYKAI_SIGNING_KEY }}`.

The job log then shows which key signed the run:

```
SIGNED BY: key 3f2a9c0d1b7e (persistent key from SAYKAI_SIGNING_KEY)
```

Without a key it shows `(this machine's local key; only this machine can
verify it)` and the action adds a notice to the run.

The key stays in your CI. The runner uses it only to sign, and removes it from
the environment before it runs any script from your repository. If
`signing-key` is set to something that is not a valid key, the run fails
rather than quietly signing with a temporary one. Pull requests from forks
cannot read secrets, so they are signed with a temporary key; that is
expected.

**Rotating the key:** run `saykai-runner keygen --out-dir new-key`, replace
the secret with the new private key, and add the new public key on a new line
of `saykai-signing.pub` (one key per line). Keep the old line so older
evidence still verifies; `verify` accepts every key in the file.

## Verifying a Safety Pack

Every run uploads its signed `safety_pack.json` as a workflow artifact,
regardless of outcome. Download it from the run's **Artifacts** section,
extract it, and check it against the public key you committed:

```
saykai-runner verify safety_pack.json --public-key saykai-signing.pub
```

`VERIFIED` means the record is exactly as it was when the run sealed it and
that your key signed it. This checks the cryptographic seal and the Ed25519
signature over the *entire* record -- not just the findings, every field -- so
an edited outcome, timestamp, or finding is detected, not just a tampered
file hash. Anyone holding the record and your public key can do this; it does
not need access to your CI or your repo. That is what makes the artifact
something you can actually hand to an auditor or attach to a change record,
rather than a JSON file that's only trustworthy as long as nobody's touched
it.

If the record is intact but was signed by a different key, `verify` says so
and names both keys. A record signed with the temporary key (no
`signing-key` set) cannot be verified by anyone afterwards, which is why the
[Signing key](#signing-key) setup matters.

To check many records in one go, `saykai-runner export --public-key
saykai-signing.pub` bundles the records in `audits/` into one file with a
verdict per record.

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
