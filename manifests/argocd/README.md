# ArgoCD runtime manifests

`runtime.yaml` is owned by the `argocd-runtime` Application.

The chosen ownership model is **raw bootstrap, intentionally**:

- ArgoCD itself is bootstrapped from the upstream manifests.
- `argocd-runtime` manages the current Deployments, StatefulSets and Services.
- `argocd-cm`, `argocd-rbac-cm`, `argocd-cmd-params-cm` and `argocd-secret` stay
  bootstrap-owned.
- Cluster RBAC and NetworkPolicies stay bootstrap-owned.
- No Helm release exists and none is planned. Mixing Helm and raw ownership is how
  the Redis HA service selectors and immutable Deployment selectors broke.

## Guardrails

- No `resources-finalizer` on `argocd-runtime`.
- `prune: false`, so a manifest edit cannot delete a live control-plane object.
- `selfHeal: true`, so drift on the owned objects is reverted.
- Do not add ConfigMaps or Secrets here.
- Do not add Redis HA here until the Helm/raw ownership question is settled.

## Redis

Redis HA was removed. ArgoCD uses the single `argocd-redis` service at
`argocd-redis:6379`. `scripts/argocd-redis-ha.yaml` remains as a reference for a
later project.

## Regenerating

Use `scripts/snapshot-argocd-runtime.sh` only when intentionally adopting changed
live objects. Review the diff before committing. The script exports Deployments,
StatefulSets and Services only.

## Lesson from the failed adoption

The chart-owned Services selected `app=redis-ha-haproxy,release=argocd`, while the
hand-applied Deployments carried only `app.kubernetes.io/name`. Zero endpoints led
to `connection refused` on cold repo-server fetches and nine Applications stuck in
`Sync=Unknown`.

The same attempt also hit immutable Deployment selectors. A chart cannot adopt a
raw install that uses different selectors. That is why this repository now keeps
the raw model deliberately.
