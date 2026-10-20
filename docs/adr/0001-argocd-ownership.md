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
  - Redis HA is enabled with three Redis/sentinel pods and three HAProxy pods.
  - Per-pod announce Services are made headless by
    `scripts/argocd-redis-ha-post-renderer.sh`. Chart 4.38.0 hardcodes ClusterIP,
    which makes sentinel monitor the Service VIP instead of the pod IP.
  - The tainted control-plane node receives explicit tolerations for Redis and
    HAProxy.
  - No raw ArgoCD manifests and no hand patches of Helm-owned workloads.

## Consequences

- `helm -n argocd history argocd` is the rollback path.
- A chart upgrade rolls the control plane; expect a brief sync pause.
  - Redis HA rollout requires the post-renderer on every Helm upgrade. A plain
    `helm upgrade` would revert the announce Services to ClusterIP and break
    sentinel discovery.
  - The Redis server ConfigMap change does not roll the ArgoCD workloads. Restart
    repo-server, server, applicationset and application-controller after the
    upgrade so they pick up the HAProxy Redis endpoint.
