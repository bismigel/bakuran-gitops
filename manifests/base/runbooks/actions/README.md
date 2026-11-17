---
type: index
audience: agent
owns: nothing — it states the format and the four authoring rules
---

# Conditions — what to run instead of what to read

Every alert, every "why is this broken", and every incident that has already been diagnosed **once** belongs here as a file
you can execute. The problem this solves is not knowledge — the estate has plenty — it is that the same investigation gets
re-read, re-typed and re-derived every time, and two people will do it in two different orders.

```
ops/run --list                     # what is registered
ops/run <id>                       # detect + diagnose. READ ONLY, always safe
ops/run <id> --remedy              # the fix, if the condition declares one
ops/run <id> --remedy --yes        # required when blast_radius is `cluster`
```

## Format (TOML, so it needs no dependency — `tomllib` is in the stdlib)

```toml
id = "egress-map-stale-ifindex"
title = "…what a human would say is happening…"
severity = "high"                 # low | medium | high
blast_radius = "node"             # node | cluster | external
reversible = true
runbook = "docs/reference/network.md#…"          # the anchor this came from
measured = "2026-11-14"           # when the diagnosis below was last proven

[detect]                          # does this condition apply at all? cheap, read-only
commands = [ "…" ]
expect = "any-fail"               # any-fail | all-pass | contains:<text>

[diagnose]                        # the deciding facts. read-only, ALWAYS
commands = [ "…" ]
verdict = "how to read the output above"

[remedy]                          # optional. classified, gated, idempotent
commands = [ "…" ]
why_safe = "one sentence a reviewer can argue with"
```

## The four rules

1. **`diagnose` is always safe and always first.** A condition must be answerable without touching anything — an operator
   at 2 a.m. needs to know whether they are looking at a real outage.
2. **`remedy` is opt-in**, classified by `blast_radius`, and refuses at `cluster` without `--yes`. ADR 0002 is not
   negotiable because a playbook finds it convenient.
3. **A remedy is idempotent**, because the first thing a runner does is run it again.
4. **A condition cites where it was measured.** `measured = <date>` is not ceremony: it is the difference between a
   diagnosis and a guess, and it is how you know to re-check after the cluster changes.

## Coverage: every alert has a decision

`scripts/check-alert-coverage.py` reads the alert rules out of `bakuran-gitops` and fails unless every one is either

- **claimed by a condition** — `alerts = ["WireGuardNoEgress"]` in the condition file, or
- **waived in `runbooks/waivers.yaml`**, in a group whose `reason` says where the operator goes instead.

Today: 72 rules, 2 claimed by three conditions, 70 waived in eleven groups, 0 undecided. Adding a rule without either fails
the build, which moves *"what happens when this fires?"* into the PR that adds it. The check also fails on a **waiver whose
alert no longer exists**, so the waiver list cannot rot.

## What does not belong here

Procedures with judgement in them (rotations, restore drills, anything with "decide whether"), and anything that deletes
state. Those stay in `OPERATIONS.md` where a human reads them, for the reason in rule 2.
