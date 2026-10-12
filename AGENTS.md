# AGENTS.md — instructions for AI/LLM agents (and humans)

This repo is the **ArgoCD desired state** for the Bakuran homelab.

**One ArgoCD control plane** runs on `sitaw-amd` (.82, AMD) and manages **both**
single-node k3s clusters:
- **sitaw-amd** (.82, AMD) — sites, APIs, platform (in-cluster)
- **calamansi-intel** (.81, Intel) — the media stack (registered as an external cluster)

There is **no CI deploy step** — changing this repo *is* deploying (ArgoCD pulls).

## Golden rules

1. **Do not put application source, Dockerfiles, or plaintext secrets here.**
   App code lives in its own repo; only `Application`/`ApplicationSet` manifests
   and cluster add-ons live here.
2. **One `Application` per workload**, in `applications/<cluster>/<name>.yaml`.
3. **Shared workloads** (run on every cluster) are an `ApplicationSet` with a
   `clusters` generator (see `applications/node-exporter-appset.yaml`).
4. Secrets must be **Sealed Secrets** (`SealedSecret` CRs) — safe to commit.
   Never commit plaintext `Secret`s, tokens, or keys. (The ArgoCD cluster
   registration in `clusters/` is applied out-of-band and redacted in git.)

## Layout

```
bootstrap/root-app.yaml          # the single root app-of-apps (on sitaw-amd)
clusters/<name>.yaml             # ArgoCD cluster registrations (redacted bootstrap)
applications/
  sitaw-amd/*.yaml                   # Applications targeting sitaw-amd (in-cluster)
  calamansi-intel/*.yaml               # Applications targeting calamansi-intel (media)
  node-exporter-appset.yaml      # ApplicationSet -> every registered cluster
manifests/<app>/*.yaml           # raw Kubernetes manifests referenced by apps
```

## Add a new application

1. Ensure the app repo has `deploy/k8s/` (Namespace, Deployment, Service,
   Ingress). Use the `homelab-app-template`.
2. Create `applications/<cluster>/<app>.yaml`:

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
       server: https://kubernetes.default.svc   # or: name: calamansi-intel
       namespace: <ns>
     syncPolicy:
       automated: { prune: true, selfHeal: true }
       syncOptions: [CreateNamespace=true]
   ```

3. Commit. ArgoCD (on sitaw-amd) picks it up within ~3 minutes.

## Cluster targeting

- **sitaw-amd (local):** `destination.server: https://kubernetes.default.svc`
- **calamansi-intel (remote):** `destination.name: calamansi-intel`

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

## Sealing a secret

```bash
kubeseal --format yaml < secret.yaml > sealed-secret.yaml
```

Each cluster has its **own** sealing key, so a `SealedSecret` must be sealed for
the cluster that will run it.
