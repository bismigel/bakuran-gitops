# ADR 0001: ArgoCD ownership

## Status

Superseded, 2026-10-20. ArgoCD is now a Helm release.

## Context

ArgoCD was installed from raw manifests. In-place Helm adoption first failed on
immutable Deployment selectors and on Service labels. The final adoption used
`helm upgrade --take-ownership --force-conflicts` after deleting the raw
Deployments and StatefulSet. Helm recreated them with the chart's labels and
selectors.

## Decision

Helm owns ArgoCD.

- Release `argocd`, chart `argo-cd` 10.10.5.
- Values live in `manifests/argocd/values.yaml`.
- `configs.cm` and `configs.secret` remain bootstrap-owned.
- Redis HA is deferred. Use single Redis until the label and sentinel issues are
  proven in a disposable environment.
- No raw ArgoCD manifests and no hand patches of Helm-owned workloads.

## Consequences

- `helm -n argocd history argocd` is the rollback path.
- A chart upgrade rolls the control plane; expect a brief sync pause.
- Redis HA is not part of the current release.
