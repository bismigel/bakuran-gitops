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

- single Redis, not HA;
- `configs.cm.create: false`;
- `configs.secret.createSecret: false`;
- `server.insecure: true`;
- two server, repo-server, applicationset and controller replicas;
- ingress on `nginx-admin` at `argocd.bismigel.dev`.

Redis HA remains deferred. Do not add it without solving the chart-owned Service
labels and the sentinel CPU issue first.

## Ownership rule

Helm owns ArgoCD now. Do not apply raw ArgoCD manifests or hand-patch its
Deployments and Services. Change values in this file and run a Helm upgrade.
