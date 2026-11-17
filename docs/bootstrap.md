# Bootstrap

Each cluster has its own root, applied **once** by hand:

```bash
kubectl -n argocd apply -f clusters/<name>/root.yaml
```

- `clusters/prod/root.yaml` → `clusters/prod/apps` (this cluster: 31 Applications)
- `clusters/staging/root.yaml` → `clusters/staging/apps` (the KVM cluster on `.83`)

Why per-cluster roots: a cluster only reconciles the paths **its own** root names, so
an environment-specific Application cannot leak into another cluster by sitting in a
directory the other root happens to recurse. The single shared root this replaced did
exactly that — a staging Application was deployed in production because `root`
recursed all of `applications/`.

After the first apply, ArgoCD owns everything below `clusters/<name>/apps`. Never
edit an Application by hand: change it here, merge, let the root reconcile.

Superseded: `bootstrap/root-app.yaml` (removed 2026-10-29).
