# AGENTS.md — instructions for AI/LLM agents (and humans)

This repo is the **ArgoCD desired state** for the Bakuran homelab. ArgoCD on the
`calamansi` (.81) and `sitaw` (.82) clusters watches this repo and reconciles it.
There is **no CI deploy step** — changing this repo *is* deploying (ArgoCD pulls).

## Golden rules

1. **Do not put application source, Dockerfiles, or plaintext secrets here.**
   App code lives in its own repo; only `Application` manifests and cluster
   add-ons live here.
2. **One `Application` per app**, file in `applications/<name>.yaml`.
3. Secrets must be **Sealed Secrets** (`SealedSecret` CRs) — safe to commit.
   Never commit plaintext `Secret`s, tokens, or keys.
4. Keep the root app (`bootstrap/root-app.yaml`) untouched unless changing the
   overall structure.

## Add a new application

1. Ensure the app repo has a `deploy/k8s/` folder with a `kustomization.yaml`
   (Namespace, Deployment, Service, Ingress). Use the `homelab-app-template`.
2. Create `applications/<app>.yaml`:

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
       server: https://kubernetes.default.svc
       namespace: <app-namespace>
     syncPolicy:
       automated: { prune: true, selfHeal: true }
       syncOptions: [CreateNamespace=true]
   ```

3. Commit. ArgoCD picks it up within ~3 minutes.

## Change something already deployed

- **App manifest change** → edit the app repo's `deploy/k8s/`, not this repo.
- **New image tag** → the app's CI bumps it (or ArgoCD Image Updater). Don't
  hand-edit image tags unless fixing an incident.
- **Infra add-on** → add an `Application` under `applications/` with
  `sync-wave: "0"`.

## Useful commands

```bash
# see what ArgoCD thinks
kubectl -n argocd get applications
kubectl -n argocd get application <name> -o jsonpath='{.status.conditions}'

# force a refresh
kubectl -n argocd annotate application <name> argocd.argoproj.io/refresh=hard --overwrite
```

## Sealing a secret

```bash
kubeseal --format yaml < secret.yaml > sealed-secret.yaml
```

Commit the `SealedSecret`; place it in the app repo's `deploy/k8s/` (it's
cluster-scoped to a namespace).
