# bakuran-gitops

**Source of truth for the *cluster* state** of the Bakuran homelab. **One ArgoCD**
runs on `sitaw-amd` (.82) and reconciles everything here across **both** clusters.
It contains **no application code and no plaintext secrets**.

## Layout

```
bootstrap/root-app.yaml     # app-of-apps: points ArgoCD at ./applications (applied once)
applications/               # one ArgoCD Application per workload (recurse)
├── sitaw/                  # -> sitaw-amd (.82, in-cluster): sites, APIs, platform
├── calamansi-intel/        # -> calamansi-intel (.81, external cluster): media
└── node-exporter-appset.yaml  # ApplicationSet -> every registered cluster
manifests/<app>/            # raw Kubernetes manifests for apps that live here
clusters/<name>.yaml        # ArgoCD cluster registrations (redacted bootstrap)
```

`manifests/` currently holds: `media`, `monitoring`, `observability`,
`external-secrets`, `ingress-headers`, `namespaces`, `homepage`, `zeroclaw`,
`node-exporter`. Some apps point at their **own** repo's `deploy/k8s/`
(`ciceley-site`, `bismigel-site`, `private-api`, `status-api`) or a Helm chart
(`ingress-nginx`, `cert-manager`, `external-secrets`, `opentelemetry-operator`).

## How it works

1. `bootstrap/root-app.yaml` is applied **once** (see `bootstrap/README.md`).
2. The root Application reconciles everything under `applications/` (recursed).
3. Each `Application` points at a path in this repo, an app repo's `deploy/k8s`,
   or a Helm chart; ArgoCD keeps it in sync (auto-sync + self-heal).
4. Sync waves (`argocd.argoproj.io/sync-wave`) order infra (`"0"`) before apps (`"1"`).

**Adding a workload** = add one file under `applications/<cluster>/`. That's it.

## Clusters

- **sitaw-amd** (.82, AMD) — hosting + platform; the ArgoCD control plane runs here.
  Target with `destination.server: https://kubernetes.default.svc`.
- **calamansi-intel** (.81, Intel) — media stack; registered as an external cluster.
  Target with `destination.name: calamansi-intel`.

## Secrets

- **Never commit plaintext secrets.** In-cluster secrets come from **Bitwarden
  Secrets Manager via External Secrets Operator** (`ClusterSecretStore/bitwarden`)
  using `ExternalSecret` / `PushSecret` CRs — see `manifests/external-secrets/`.
- Host secrets (cloudflared creds, age identity) are **SOPS/age** (`sops-nix`),
  not in this repo's plaintext either.
- Sealed Secrets is **no longer used**.

## Commands

```bash
# run against the control plane (sitaw-amd)
kubectl -n argocd get applications
kubectl -n argocd get application <name> -o jsonpath='{.status.sync.status}'
kubectl -n argocd annotate application <name> argocd.argoproj.io/refresh=hard --overwrite
```
