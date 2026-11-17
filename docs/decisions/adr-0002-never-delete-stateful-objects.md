<!-- Mirrored from homelab-context/docs/decisions/ on 2026-11-18. The original is authoritative; if this copy and that one
     disagree, that one is right. It is here because the reasoning is the part of this estate that is hardest to fake, and
     because a reviewer should not have to ask for it. -->

# 0002 — PVC/PV/Namespace deletion is refused, not discouraged

**Status:** accepted (2026-10-29)

## Context

A bulk `delete pvc --all` aimed at staging's `books` namespace hit **production's**
identically-named namespace and destroyed three config volumes. Staging and production share
namespace names, and a `--all` in the wrong context deletes data that no backup covers
immediately.

## Decision

A ValidatingAdmissionPolicy (`protect-stateful-objects`) refuses deletion of PVC, PV and
Namespace unless the object carries `bakuran.dev/allow-delete: "true"`. Deleting one is a
runbook-17 operation: one object, by name, after checking which cluster you are on.

## Consequences

- The policy is a **backstop, not permission** — an annotation does not make a deletion wise.
- Legitimate deletes need the annotation first, which is the point: it forces one deliberate step.
- A deletion that is genuinely required still stops and asks a human.

## Evidence

`bakuran-gitops/manifests/base/guardrails/protect-stateful-objects.yaml`; runbook 17.
