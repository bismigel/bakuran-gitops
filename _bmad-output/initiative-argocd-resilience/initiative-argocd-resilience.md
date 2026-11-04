---
id: initiative-argocd-resilience
type: initiative
title: "ArgoCD survives a node going away"
parent:
covers:
sources:
  - manifests/argocd/values.yaml
  - manifests/argocd/README.md
  - docs/adr/0001-argocd-ownership.md
companions: []
after: []
refined: true
hitl: false
risk: [medium]
---

# ArgoCD survives a node going away

## Description

ArgoCD runs two replicas of each component, and tonight's audit found the redundancy is real but
**accidental**: `argocd-server` happened to land on `calamansi-intel` + `sitaw-amd` and
`repo-server` on `sitaw-amd` + `patola-thinkcentre`, with **no PodDisruptionBudgets anywhere in
the namespace**. Two consequences: a node drain may evict both replicas at once, and a future
reschedule could put both on one node without anyone noticing until that node fails.

This is the pilot for running work through BMad in this repository: one initiative, one epic, two
stories, each with a `verify:` that is actually run before the story is called done.

## Outcome

Losing any single node costs half of ArgoCD's capacity, never all of it, and that is a property of
the manifests rather than of where the scheduler happened to place a pod.

## Requirements

1. **R1** (values.yaml): a drain of one node cannot evict both replicas of `server` or
   `repoServer` — a PDB guards each.
2. **R2** (values.yaml): the two replicas of `server` and `repoServer` are on different nodes by
   declaration, not by luck.
