<!-- Mirrored from homelab-context/docs/decisions/ on 2026-11-18. The original is authoritative; if this copy and that one
     disagree, that one is right. It is here because the reasoning is the part of this estate that is hardest to fake, and
     because a reviewer should not have to ask for it. -->

# ADR 0018 — The alert lifecycle has two folders, not one, and two objects, not seventy-two

**Status:** accepted 2026-11-17. Records a design that was measured, chosen, and then lost to a session reset on
2026-11-16 — written down here so it does not have to be re-derived a third time.

## Context

The estate wants one pane of glass for runbook actions: something is firing, and both an agent and a human should reach
the same diagnosis in one step, deterministically, without reading prose and re-deriving it. The purpose is stated in the
operator's own words: **one action must have one runbook and the scripts that diagnose it (and fix it, when it is safe to),
in a single pane**.

Measured 2026-11-16 and 2026-11-17, before deciding anything:

| fact | value |
|---|---|
| alert rules that ship | **72** |
| workflow templates generated for them | 72, with **3 distinct step bodies** (70 byte-identical) |
| registered procedures (`runbooks/conditions/`) | **4** |
| alerts with a real procedure | **2** (`condition=<id>` in `runbook-index`) |
| alerts whose row says `condition=-` | **70** |
| runbook pages the alerts point at | **5** serving 72 alerts (22 · 22 · 20 · 7 · 1) |
| headings in those 5 pages | 88 — one per alert, so the per-action text exists |
| runnable command blocks in the site's org pages | **123** `#+begin_src` |
| templates that run a procedure | **0** — they print a pointer to the prose |
| `argo-workflow` ServiceAccount | **cluster-admin** (debt, story R.9) |
| artifact repository | none — reports come from pod logs, truncated at 40 lines |

Two independent sources decided the shape:

- **Google SRE Workbook, On-Call** (`https://sre.google/workbook/on-call/`): "Whenever an alert is created, a
  corresponding playbook entry is usually created… **Details in playbooks go out of date at the same rate as production
  environment changes.**" A procedure maintained separately from its trigger will rot; the only defence is that both are
  created and reviewed together.
- **Argo Workflows, Workflow Templates** (`https://argo-workflows.readthedocs.io/en/latest/workflow-templates/`):
  templates exist so you can "create a **library of frequently-used templates** and reuse them either by submitting them
  directly or by referencing them from your Workflows". Seventy-two templates with three bodies is the documented
  anti-pattern.

## Decision

### 1. Two folders, because triggers and procedures are reviewed for different things

```
bakuran-gitops/manifests/base/
  monitoring/
    rules/                  # TRIGGERS — what fires. One file per concern.
      alerting.yaml  alerting-workloads.yaml  alerting-network-devices.yaml
    checks/                 # the CronJobs that produce metrics or push alerts (login-alerts.yaml is one)
    checks/                 # the CronJob probes that produce some of the metrics
    dashboards/  exporters/
  runbooks/
    actions/<id>.yaml       # PROCEDURES — the only place a procedure is written
    waivers.yaml            # the alerts decided NOT to script, each naming where the human goes
    index.yaml              # GENERATED: alert -> {action, severity, runbook_url}
    templates/action.yaml   # GENERATED: runs an action in-cluster
    templates/diag.yaml     # GENERATED: evidence only, the fallback
    rbac.yaml               # derived from the actions' commands (closes R.9)
```

**Not** a single `alerts/` tree holding rules, procedures, templates and dashboards. It reads well in a screenshot and
costs the property that matters: a rule is reviewed for paging behaviour ("will this page me wrongly?"), a procedure for
safety ("is this fix safe?"), and a reviewer who is handed both in one file skims one of them. They also change at
different rates and belong to different Kubernetes objects.

`runbooks/actions/` keeps the name `conditions/` may keep its `.yaml` files as they are: the *folder* is cosmetic as long
as one file owns one action. The rename is worth doing because "action" is the pane's vocabulary and because
`waivers.yaml` is a decision *about* actions, not an action.

### 2. Two objects, because per-alert is a data relationship

The pane holds **two** WorkflowTemplates:

- `diag` — evidence only: pods, events, logs. The fallback for alerts with no procedure.
- `action` — runs the action's own `diagnose` in-cluster.

and the alert→action relationship is a **row** in the generated `runbook-index` ConfigMap, not an object. Collapsing 72
objects to two is what stops ArgoCD's application controller carrying a lookup table as a hundred API objects — the
controller had been OOM-killed 25 times at a 2 Gi limit before this was measured.

### 3. A procedure produces a verdict, not a log

An action's run must end in a bounded, machine-readable result: `ops-run <id> --json` writes a small JSON verdict, the
step declares `outputs.parameters` with `valueFrom: path:` (Argo's documented mechanism —
`https://argo-workflows.readthedocs.io/en/latest/walk-through/output-parameters/`), and both consumers print **that field**
rather than the logs. Without it, "deterministic diagnosis" is truncation dressed up as determinism.

### 4. One entry point per consumer, one key

- agent / workstation: `ops-run <id>` (and `<alert name>` resolves through the index)
- cluster: the same binary in a small image, run by `templates/action.yaml`
- human: **Argo's own UI** behind the admin ingress and Cloudflare Access. No second UI, no bespoke dashboard over 72
  templates — the engine's UI is the pane once it is reachable.

One owner per fact (ADR 0011): the procedure is written once, the alert→action link is one generated row, the evidence
commands are written once, and the RBAC surface is the union of the `commands` in the action files — a finite list that
can be *read*, which is how R.9 closes rather than being waved at.

## Consequences

- **Coverage is the real backlog, and it is now a number.** 70 of 72 alerts have no procedure. The material exists — 88
  headings and 123 command blocks in the five pages — but nothing binds a block to an alert. The pane will look empty
  until that is worked through, and no amount of folder tidying changes it.
- **The waivers must name an anchor.** Today a waiver says `runbook 25`, sending the reader to a 220-line page. An anchor
  is a one-hour change that halves the reading cost immediately, and it is also what makes "waived" an honest decision
  rather than a shrug.
- **Deletion list**, once `action.yaml` exists: the per-alert template generator, the `collect`/`note` machinery, and the
  cluster-admin binding.
- **This ADR does not decide the site.** The prose stays in `bismigel-site` (`org/runbook/*.org`), and the action file
  carries the anchor. If the two ever disagree, `check-runbook-links` catches the anchor and nothing catches the prose —
  stated here as the known weak seam rather than pretended away.
- **R.10 is not this.** `gen-runbooks.py` used to defer "not in-cluster — see R.10", and no such story exists. The
  question it stood for is answered above (an action runs in-cluster through `templates/action.yaml`); the dangling
  reference is replaced by this ADR.
