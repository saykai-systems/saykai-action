# Quickstart

A real, working `saykai.yml` + `saykai-policy.yml` pair — copy this
directory into your own repo as a starting point. Everything in here has
been run and verified against a real build of `saykai-runner`; it isn't
illustrative pseudo-config.

(If you're looking at `saykai-examples` instead: that repo is deliberately
sanitized, non-executable reference material for security review, not a
template. This directory is the real thing.)

## Using this

1. Copy `saykai.yml`, `saykai-policy.yml`, and (optionally) `scan_targets/`
   into your own repo.
2. Point `saykai.yml`'s `scan.root` at wherever your real Nav2 params
   actually live (delete the placeholder `scan_targets/` once you've
   confirmed the gate runs cleanly against it).
3. **Do not treat `saykai-policy.yml`'s `hard_limits` as safe defaults for
   your robot.** They're illustrative starting values only. Run
   `saykai-runner calibrate` with your robot's real sensor range,
   perception latency, and achievable braking deceleration to get a
   physics-derived suggestion, then have a qualified safety engineer
   review and approve whatever you end up using — see the derivation
   comments in `saykai-policy.yml` and the main README's Configuration
   section.
4. Add the workflow step from the main README, pointing `spec-path` at
   wherever you put `saykai.yml`.

## What's in here

- `saykai.yml` — project spec: where to scan, which policy file to use.
- `saykai-policy.yml` — thresholds and rules, with every field commented.
  Includes the Room 2 (behavioral simulation) schema, left empty
  (`scenarios: []`) since most repos won't have a `robot_brain.py` on day
  one — delete that section entirely if you never plan to use it.
- `scan_targets/nav2_params.yaml` — a placeholder Nav2 config that passes
  cleanly against the starter thresholds, so you can confirm the gate
  works end-to-end before pointing it at your real config.
