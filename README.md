# bakuran-gitops

## Why "Bakuran"

Bakuran is Tagalog for the yard or enclosure behind a house, from *bakod*, a
fence. It is the space where things get built, repaired, and occasionally taken
apart to see how they work. This repo is part of that backyard lab: small,
personal, and safe to break on purpose.

  **Source of truth for the *cluster* state** of the Bakuran homelab. **One ArgoCD**
  runs on `sitaw-amd` (.82) and reconciles everything here across the **one 3-node
  k3s cluster**. It contains **no application code and no plaintext secrets**.
  ArgoCD is the Helm release `argocd`, chart `argo-cd` 10.10.5, not a raw manifest
  install.

## Layout

```
bootstrap/root-app.yaml     # app-of-apps: points ArgoCD at ./applications (applied once)
applications/               # one ArgoCD Application per workload (recursed)
├── sitaw/                  # platform + apps (in-cluster)
├── calamansi-intel/media.yaml  # the media app (still in-cluster, pinned to .81)
└── node-exporter-appset.yaml   # ApplicationSet -> every node
manifests/<app>/            # raw Kubernetes manifests
scripts/                    # generators (e.g. generate-duwende-context.sh)
```

`manifests/` currently holds: `media` (the *arr stack + **media-mcp**), `books`
(Kavita, LazyLibrarian, **Audiobookshelf**), `monitoring` (incl. the **login watchers**
and the power dashboard), `observability`, `external-secrets`, `ingress-headers`,
`namespaces`, `homepage`, `duwende` (config + **generated** context), `kepler`,
`immich`, `karakeep`, `cilium`, `edge`, `network-policies`, `intel-gpu-plugin`,
`longhorn-config`, `argocd`, `node-exporter`. Some apps point at their **own** repo's
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
    `NoSchedule`-tainted; **Immich** and one **Redis HA** replica tolerate the
    taint. Immich keeps its database and library on `/mnt/data`; its ML worker
    runs on `.82`.

  All workloads target `destination.server: https://kubernetes.default.svc` — there
  are **no external cluster registrations**. Networking is Cilium VXLAN with
  kube-proxy retained.

## ArgoCD and Redis

  Redis HA runs three Redis/sentinel pods and three HAProxy pods. The chart
  hardcodes the per-pod announce Services as ClusterIP, so the Helm post-renderer
  `scripts/argocd-redis-ha-post-renderer.sh` makes them headless. Keep it on every
  ArgoCD upgrade. The Redis endpoint is `argocd-redis-ha-haproxy:6379`.

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

# regenerate the Duwende knowledge base after editing ~/projects/homelab-context
./scripts/generate-duwende-context.sh
```
