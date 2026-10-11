# bakuran-gitops

**Source of truth for the *cluster* state** of the Bakuran homelab. ArgoCD
watches this repo and reconciles everything here. It contains **no application
code and no secrets in plaintext**.

```
bootstrap/root-app.yaml        # app-of-apps (points ArgoCD at ./applications)
applications/                  # one ArgoCD Application per thing to deploy
├── ciceley-site.yaml          # app  (points at an app repo's deploy/k8s)
└── sealed-secrets.yaml        # infra add-on
infra/                         # reference Applications not yet adopted
└── ingress-nginx.yaml
```

## How it works

1. `bootstrap/root-app.yaml` is applied **once** (see below).
2. The root Application reconciles everything under `applications/` (recursed).
3. Each `Application` points at either an app repo's `deploy/k8s` path or a Helm
   chart, and ArgoCD keeps it in sync.
4. Sync waves (`argocd.argoproj.io/sync-wave`) order infra before apps.

**Adding an application** = add one file in `applications/` pointing at a repo +
path. That's it.

## Bootstrap (once per cluster)

```bash
kubectl apply -f bootstrap/root-app.yaml
```

ArgoCD needs read access to this (private) repo via a deploy key stored as a
repo secret in the `argocd` namespace.

## Conventions

- One `Application` per app; filename = app name.
- Apps live in their **own** repos and own their `deploy/k8s` manifests.
- Infra add-ons get `sync-wave: "0"`, apps `sync-wave: "1"`.
- Secrets are **Sealed Secrets** (safe to commit) — never plaintext.
