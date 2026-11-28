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

- Release `argocd`, chart `argo-cd` 10.19.1 (application version `v3.6.3`).
- Values live in `install/argocd/values.yaml`.
- `configs.cm` is Helm-owned (`configs.cm.create: true`, changed in #194) so the
  customizations and exclusions it carries are declared rather than hand-patched;
  `configs.secret` remains bootstrap-owned.
  - Redis HA is enabled with three Redis/sentinel pods and three HAProxy pods.
  - Per-pod announce Services are made headless by the
    `argocd-redis-ha-post-renderer` command (Go, in `homelab-context`, ADR 0016;
    invoked as `--post-renderer` under Helm 3). Chart 4.38.0 hardcodes ClusterIP,
    which makes sentinel monitor the Service VIP instead of the pod IP.
  - `argocd-server` runs with `server.insecure: true` and serves plain HTTP, so the
    Ingress backend is port 80. The Ingress object itself is owned by
    `manifests/base/argocd-ha/ingress.yaml` (`server.ingress.enabled: false` in the
    values file): one owner per object, ADR 0011.
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
