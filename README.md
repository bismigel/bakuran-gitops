# bakuran-gitops

**Source of truth for the *cluster* state** of the Bakuran homelab. **One ArgoCD**
runs on `sitaw-amd` (.82) and reconciles everything here across the **one 3-node
k3s cluster**. It contains **no application code and no plaintext secrets**.

## Layout

```
bootstrap/root-app.yaml     # app-of-apps: points ArgoCD at ./applications (applied once)
applications/               # one ArgoCD Application per workload (recursed)
├── sitaw/                  # platform + apps (in-cluster)
└── node-exporter-appset.yaml  # ApplicationSet -> every node
manifests/<app>/            # raw Kubernetes manifests
scripts/                    # generators (e.g. generate-zeroclaw-context.sh)
```

`manifests/` currently holds: `media`, `monitoring` (incl. the **login watchers**
and the power dashboard), `observability`, `external-secrets`, `ingress-headers`,
`namespaces`, `homepage`, `zeroclaw` (config + **generated** context), `kepler`,
`immich`, `longhorn-config`, `node-exporter`. Some apps point at their **own** repo's
`deploy/k8s/` (`ciceley-site`, `bismigel-site`, `private-api`, `status-api`) or a
Helm chart (`ingress-nginx`, `cert-manager`, `external-secrets`,
`opentelemetry-operator`).

## How it works

1. `bootstrap/root-app.yaml` is applied **once** (see `bootstrap/README.md`).
2. The root Application reconciles everything under `applications/` (recursed).
3. Each `Application` points at a path in this repo, an app repo's `deploy/k8s`,
   or a Helm chart; ArgoCD keeps it in sync (auto-sync + self-heal).
4. Sync waves (`argocd.argoproj.io/sync-wave`) order infra (`"0"`) before apps (`"1"`).

**Adding a workload** = add one file under `applications/sitaw/`. That's it.

## Cluster

One **3-node k3s cluster** (embedded etcd, 3 members) — everything is `in-cluster`:

- **sitaw-amd** (.82, AMD) — platform: ArgoCD, ingress-nginx, monitoring, sites/APIs.
- **calamansi-intel** (.81, Intel) — media (pinned by `nodeSelector`).
- **kamatis-mbp** (.83, MacBook Pro 2012) — 3rd etcd/control-plane node,
  `NoSchedule`-tainted; **Immich** tolerates the taint and runs there
  (server/postgres/valkey, storage on `/mnt/data`; its ML runs on `.82`).

All workloads target `destination.server: https://kubernetes.default.svc` — there
are **no external cluster registrations**.

## Edge (Cloudflare)

The edge is declared in **`bakuran-infra/cloudflare/sync.sh`** and reconciled
**daily** by a systemd timer on `.82`. Jellyfin and Immich are intentionally **not**
behind Cloudflare Access (native TV/phone clients can't complete the email-OTP);
the admin/media apps are. Admin apps use a 24h Access session, media 730h.

## Secrets

- **Never commit plaintext secrets.** In-cluster secrets come from **Bitwarden
  Secrets Manager via External Secrets Operator** (`ClusterSecretStore/bitwarden`)
  using `ExternalSecret` / `PushSecret` CRs — see `manifests/external-secrets/`.
- Host secrets (cloudflared creds, ProtonVPN key, Cloudflare token, age identity)
  are **SOPS/age** (`sops-nix`), not in this repo.
- Sealed Secrets is **no longer used**.

## Commands

```bash
# run against the control plane (sitaw-amd)
kubectl -n argocd get applications
kubectl -n argocd get application <name> -o jsonpath='{.status.sync.status}'
kubectl -n argocd annotate application <name> argocd.argoproj.io/refresh=hard --overwrite

# regenerate the ZeroClaw knowledge base after editing ~/projects/homelab-context
./scripts/generate-zeroclaw-context.sh
```
