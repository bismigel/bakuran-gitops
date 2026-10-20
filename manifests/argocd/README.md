# ArgoCD ownership

ArgoCD is now a Helm release:

- release: `argocd`
- chart: `argo-cd` `10.10.5`
- application version: `v3.5.5`
- namespace: `argocd`

The release was adopted in place with:

```bash
helm -n argocd upgrade --install argocd argo/argo-cd \
  --version 10.10.5 -f manifests/argocd/values.yaml \
  --take-ownership --force-conflicts
```

The existing Deployments had immutable selectors from the raw install, so they
were deleted and recreated by Helm. Services, ConfigMaps, secrets and RBAC were
adopted with `--take-ownership`.

## Current values

- Redis HA with three Redis/sentinel pods and three HAProxy pods;
- headless per-pod announce Services via the post-renderer below;
- control-plane tolerations for the tainted third node;
- `configs.cm.create: false`;
- `configs.secret.createSecret: false`;
- `server.insecure: true`;
- two server, repo-server, applicationset and controller replicas;
- ingress on `nginx-admin` at `argocd.bismigel.dev`.

Chart `redis-ha` 4.38.0 hardcodes announce Services as ClusterIP. That makes
sentinel monitor the Service VIP instead of its pod. The fix is a Helm
post-renderer that changes those Services to headless while keeping
`publishNotReadyAddresses: true`.

## Upgrade

```bash
helm -n argocd upgrade --install argocd argo/argo-cd \
  --version 10.10.5 -f manifests/argocd/values.yaml \
  --post-renderer ./scripts/argocd-redis-ha-post-renderer.sh \
  --take-ownership --force-conflicts --wait --timeout 10m
```

Rollback path:

```bash
helm -n argocd rollback argocd
```

## Ownership rule

Helm owns ArgoCD now. Do not apply raw ArgoCD manifests or hand-patch its
Deployments and Services. Change values in this file and run a Helm upgrade.
