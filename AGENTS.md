# AGENTS.md — instructions for AI/LLM agents (and humans)

This repo is the **ArgoCD desired state** for the Bakuran homelab.

**One ArgoCD control plane** runs on `sitaw-amd` (.82, AMD) and manages **one
3-node k3s cluster** (embedded etcd, 3 members):
- **sitaw-amd** (.82, AMD) — platform + sites/APIs (in-cluster)
- **calamansi-intel** (.81, Intel) — the media stack (in-cluster, pinned via `nodeSelector`)
- **kamatis-mbp** (.83, MacBook) — 3rd etcd node (tainted); **Immich** runs there

The Cloudflare edge (tunnel/DNS/Access) is **not** in this repo — it lives in
`bakuran-infra/cloudflare/sync.sh` and is reconciled daily on `.82`.

There is **no CI deploy step** — changing this repo *is* deploying (ArgoCD pulls).

## Golden rules

1. **Do not put application source, Dockerfiles, or plaintext secrets here.**
   App code lives in its own repo; only `Application`/`ApplicationSet` manifests
   and cluster add-ons live here.
2. **One `Application` per workload**, in `applications/<cluster>/<name>.yaml`.
3. **Shared workloads** (run on every cluster) are an `ApplicationSet` with a
   `clusters` generator (see `applications/node-exporter-appset.yaml`).
4. Never commit plaintext `Secret`s, tokens, or keys. In-cluster secrets are
   **Bitwarden Secrets Manager + External Secrets Operator**
   (`ExternalSecret`/`PushSecret` against `ClusterSecretStore/bitwarden`). Host
   secrets are **SOPS/age** (`sops-nix`). (The ArgoCD cluster registration in
   `clusters/` is applied out-of-band and redacted in git.)

## Layout

```
bootstrap/root-app.yaml          # the single root app-of-apps (on sitaw-amd)
applications/
  sitaw/*.yaml                   # platform + apps (in-cluster)
  calamansi-intel/media.yaml     # the media app (in-cluster, pinned to .81)
  node-exporter-appset.yaml      # ApplicationSet -> every node
manifests/<app>/*.yaml           # raw Kubernetes manifests referenced by apps
scripts/                         # generators (generate-duwende-context.sh)
```

## Add a new application

1. Ensure the app repo has `deploy/k8s/` (Namespace, Deployment, Service,
   Ingress). Use the `homelab-app-template`.
2. Create `applications/sitaw/<app>.yaml`:

   ```yaml
   apiVersion: argoproj.io/v1alpha1
   kind: Application
   metadata:
     name: <app>
     namespace: argocd
     annotations:
       argocd.argoproj.io/sync-wave: "1"   # infra = 0, apps = 1
     finalizers:
       - resources-finalizer.argocd.argoproj.io
   spec:
     project: default
     source:
       repoURL: https://github.com/<owner>/<repo>
       targetRevision: main
       path: deploy/k8s
     destination:
       server: https://kubernetes.default.svc   # everything is in-cluster
       namespace: <ns>
     syncPolicy:
       automated: { prune: true, selfHeal: true }
       syncOptions: [CreateNamespace=true]
   ```

3. Commit. ArgoCD (on sitaw-amd) picks it up within ~3 minutes.

> If the manifests live **in this repo** instead of the app repo, set
> `repoURL: git@github.com:bismigel/bakuran-gitops.git` and `path: manifests/<app>`
> (this is how `media`, `monitoring`, `duwende`, etc. are wired).

## Cluster targeting

Use `destination.server: https://kubernetes.default.svc` for everything — there
are no external cluster registrations. Pin a workload to a node with `nodeSelector`
(e.g. media → `.81`, Immich → `.83`).

## Change something already deployed

- **App manifest change** → edit the app repo's `deploy/k8s/`, not this repo.
- **New image tag** → the app's CI bumps it. Don't hand-edit tags.
- **Cluster add-on** → new file under `applications/<cluster>/` with
  `sync-wave: "0"`.

## Useful commands

```bash
# run against the control plane (sitaw-amd)
kubectl -n argocd get applications
kubectl -n argocd get applicationsets
kubectl -n argocd get application <name> -o jsonpath='{.status.conditions}'

# force a refresh
kubectl -n argocd annotate application <name> argocd.argoproj.io/refresh=hard --overwrite
```

## Secrets (Bitwarden + ESO)

Reference a Bitwarden Secrets Manager secret with an `ExternalSecret`:

```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata: { name: my-secret, namespace: apps }
spec:
  refreshInterval: 1h
  secretStoreRef: { kind: ClusterSecretStore, name: bitwarden }
  target: { name: my-secret }
  data:
    - secretKey: token
      remoteRef: { key: my-secret }   # the Bitwarden secret's name
```

Create/rotate the real value in the **Bitwarden web vault** (Secrets Manager), or
push one up with a `PushSecret`. Secrets materialize on the cluster; nothing is
committed. Sealed Secrets is no longer used.
