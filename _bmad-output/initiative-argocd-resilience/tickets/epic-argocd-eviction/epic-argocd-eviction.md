---
id: 1
type: epic
title: "A node drain cannot take ArgoCD below one replica"
parent: initiative-argocd-resilience
covers: [R1, R2]
sources: [manifests/argocd/values.yaml]
companions: []
after: []
refined: true
hitl: false
risk: [medium]
---

# A node drain cannot take ArgoCD below one replica

## Description

Both guarantees live in the Helm values, so both are one-line-per-component changes with a
verification that is a `kubectl get`. The reason to do it in this repo, at this size, is that it
is the smallest change that exercises the BMad flow end to end without inventing work.

## Outcome

Draining a node leaves ArgoCD managing the cluster with at least one server and one repo-server,
and the placement rule is visible in review instead of inferred from `kubectl get pods -o wide`.

## Done when

- `server.pdb` and `repoServer.pdb` are enabled at `minAvailable: 1`.
- Both Deployments carry **required** host anti-affinity against their own component label.
- The live namespace shows both PDBs, `ALLOWED DISRUPTIONS 1`, and the replicas on separate nodes.
