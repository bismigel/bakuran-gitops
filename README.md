# bakuran-gitops

> **This repository's origin is Forgejo** ([git.bismigel.dev](https://git.bismigel.dev)). GitHub receives a push mirror,
> so what you read here is current, but pull requests, CI and reviews happen there. Everything below describes the
> repository itself and is the same on both sides.


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
clusters/<name>/root.yaml        # app-of-apps per cluster (applied once): prod, staging
clusters/<name>/apps/            # one ArgoCD Application per workload (recursed)
  platform/                      # infra that must exist before workloads
  workloads/                     # the things a human uses
  staging/                       # <- removed 2026-10-30, see below
  node-exporter-appset.yaml      # ApplicationSet -> every node
clusters/<name>/projects/        # the AppProject objects (root's SECOND source)
manifests/base/<component>/      # cluster-agnostic definitions
manifests/overlays/<env>/<c>/    # what one environment changes: placement, storage, refs
scripts/                         # generators (e.g. generate-duwende-context.sh)
```

**Three components have been split into base + overlay** (`media`, `books`,
`monitoring`): the base holds the definitions, the overlay holds placement
(`nodeSelector: media-pool`), storage class, and environment-only objects. The prod
render of each is byte-identical to what it replaced, which is how the split was
proven safe. The remaining components are still single-directory
(`manifests/<component>/`) until each is split the same way — a deliberate,
reversible order rather than a flag day. Those are: `observability`,
`external-secrets`, `ingress-headers`, `namespaces`, `homepage`, `duwende`,
`kepler`, `immich`, `karakeep`, `cilium`, `edge`, `network-policies`,
`intel-gpu-plugin`, `longhorn-config`, `argocd`, `node-exporter`,
`guardrails`.

Some apps point at their **own** repo's `deploy/k8s/` (`ciceley-site`,
`bismigel-site`, `private-api`, `status-api`) or a Helm chart (`ingress-nginx`,
`cert-manager`, `external-secrets`, `opentelemetry-operator`).

### `clusters/prod/apps/staging/` is gone (2026-10-30)

`status-api-staging` was a *staging* overlay deployed into *production* — a leftover
from before the per-cluster roots, kept because removing it prunes a namespace. Its
replacement is staging's own cluster: the same overlay now runs where it was meant to,
and production no longer carries an Application whose name says another environment.

## How it works

1. `clusters/<name>/root.yaml` is applied **once** per cluster (`kubectl apply -f
   clusters/prod/root.yaml`). It is the only hand-applied object left; everything
   below it, including the AppProjects, is reconciled.
2. Each root Application reconciles everything under its own `clusters/<name>/apps/`
   (recursed) **and** the AppProjects in `clusters/<name>/projects/`.
3. Each `Application` points at a path in this repo, an app repo's `deploy/k8s`,
   or a Helm chart; ArgoCD keeps it in sync (auto-sync + self-heal).
4. Sync waves (`argocd.argoproj.io/sync-wave`) order infra (`"0"`) before apps (`"1"`).

**Adding a workload** = one file under `clusters/prod/apps/workloads/` (or
`platform/` if it must exist first). That's it.

## Cluster

One **3-node k3s cluster** (embedded etcd, 3 members) — everything is `in-cluster`:

- **sitaw-amd** (.82, AMD) — platform: ArgoCD, ingress-nginx, monitoring, sites/APIs,
  the NFS server, cloudflared.
- **calamansi-intel** (.81, Intel) — media (pinned by `nodeSelector`), the mergerfs
  pool at `/mnt/media`, both Cloudflare Tunnel connectors, the WireGuard tunnel.
- **patola-thinkcentre** (.80, Intel ThinkCentre) — 3rd etcd member, and where
  **Immich** lives (server, Postgres, Redis; the ML worker runs on `.82`).

All three are control-plane **and** schedulable; none is tainted. **No node is
special**: losing any one leaves quorum and a working API (the VIP sits at
`192.168.2.100`, held by whichever node wins the lease).

`.83` (`kamatis-mbp`, the 2012 MacBook) is **not** a cluster member — it is the
**staging host**: it runs the KVM guests that form the rehearsal cluster, which pulls
this same repo through `clusters/staging/`.

Immich historically lived on `/mnt/data` on `.83`; it moved to Longhorn on `.80` when
`.83` was repurposed. If you find a reference to `/mnt/data` or to Immich on
`kamatis-mbp`, it is pre-2026-10-28.

All workloads target `destination.server: https://kubernetes.default.svc` — there
are **no external cluster registrations**. Networking is Cilium VXLAN with
kube-proxy retained.

## ArgoCD and Redis

  Redis HA runs three Redis/sentinel pods and three HAProxy pods. The chart
  hardcodes the per-pod announce Services as ClusterIP, so the Helm post-renderer
  `scripts/argocd-redis-ha-post-renderer.sh` makes them headless. Keep it on every
  ArgoCD upgrade. The Redis endpoint is `argocd-redis-ha-haproxy:6379`.

## Edge (Cloudflare)

The edge is declared in **`bakuran-infra/opentofu/cloudflare/`** (OpenTofu): DNS
records, tunnel ingress, Access apps, zone settings and R2 lifecycle, planned and
applied with `tofu` against state in the R2 backend.

`bakuran-infra/cloudflare/sync.sh` is **retired** — a manual rollback path only —
and the daily `cloudflare-sync.timer` is gone, so it cannot fight the OpenTofu
state. A new hostname means a record in `records_all.tf` **and** an ingress entry
in `tunnel.tf`.

Jellyfin, Immich, Kavita and Audiobookshelf are intentionally **not** behind
Cloudflare Access (native TV/phone/mobile clients can't complete the email-OTP);
they rely on their own auth. Access-gated apps: Books, Longhorn, Private API,
Homelab Agent, Runbook and Grafana at a **24h** session, Homelab Media at **730h**.

## Guardrails

Four layers, each of which turns a class of mistake into something loud rather than
silent. They are listed in the order they catch things:

1. **CI (before merge)** — four required checks: `yamllint` over every manifest and the image
   digests are pinned and current; the manifest layout and duplicate objects; every alert's
   `runbook_url` resolves to a page and an anchor in the site repo; and an image scan against
   `scripts/scan-baseline.json`, which fails on a finding that is not baselined *and* on a
   baseline entry for an image nobody deploys, so the count can only go down.
   A glob that matches nothing is a **hard error** — one check had silently validated nothing
   for days because its glob was empty after a move.

   Workstation-only, and named here rather than implied: `kubeconform`, `conftest`/OPA policy on
   the rendered output, `gitleaks` and `promtool` all need tools the CI runner does not carry, so
   they are run by hand before a change leaves the laptop. That is weaker than a gate and this
   paragraph used to claim otherwise.
2. **AppProject (blast radius)** — every Application runs in `prod` or `staging`, never
   `default`. The project lists exactly the namespaces and source repos an app may
   touch, so a wrong `destination.namespace` is an API rejection instead of an
   incident. `namespaceResourceBlacklist` is deliberately **not** used: it is not
   namespace-scoped, so blacklisting one kind blocks it everywhere.
3. **`ValidatingAdmissionPolicy protect-stateful-objects` (at the API)** — `DELETE` on
   a `PersistentVolumeClaim`, `PersistentVolume` or `Namespace` is **denied** unless the
   object carries `bakuran.dev/allow-delete: "true"`. It matches `oldObject`, because
   a DELETE request has no `object`. This exists because a `kubectl delete pvc --all`
   aimed at staging's namespace hit production's identically-named one and destroyed
   three volumes. Break-glass is one annotation; the denial explains itself.
4. **Pod Security Admission** — every namespace this repo owns states an explicit
   level (`enforce: baseline` or `privileged` with a recorded reason), and CI fails on
   silence, so "no label" can never be mistaken for "decided".

Details and the exact commands: `homelab-context/HARDENING.md`, and runbook 17 for the
deletion policy.

## Secrets

- **Never commit plaintext secrets.** In-cluster secrets come from **Bitwarden
  Secrets Manager via External Secrets Operator** (`ClusterSecretStore/bitwarden`)
  using `ExternalSecret` / `PushSecret` CRs — see `manifests/base/external-secrets/`.
- **Every Secret is ESO-owned.** The last hand-applied ones (`books/kavita-secrets`,
  `books/lazylibrarian-secrets`) were adopted on 2026-10-29 with
  `creationPolicy: Owner` — the object is updated in place, so a running pod never sees
  it missing — and the script that used to write them is deleted. A `ClusterSecretStore`
  is usable from **every** namespace, so "this namespace has no ESO" is never a reason
  to hand-write a Secret.
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

## What owns what

| directory | what it is | applied by |
|---|---|---|
| `clusters/prod/root.yaml` | the app-of-apps root | ArgoCD, once, by hand |
| `clusters/prod/apps/` | one `Application` per component, in sync waves | the root app |
| `clusters/prod/projects/` | the `prod` AppProject: destinations, `sourceRepos`, cluster-scoped whitelist | the root app |
| `manifests/base/<component>/` | the manifests for a component | its `Application` |
| `manifests/overlays/prod/<component>/` | what differs in production (placement, replicas, patches) | its `Application` |
| `scripts/` | checks that run in CI and by hand (`generate-duwende-context.sh`, `check-runbook-links.py`, …) | you, and `.github/workflows/` |

Two things that catch people out:

- **`clusters/prod/projects/projects.yaml` gates everything.** A new repo needs a `sourceRepos` entry and a new namespace a
  `destinations` entry, or the Application fails to sync with a message that looks like a permissions bug.
- **`manifests/duwende/context.yaml` is generated** from the private `homelab-context` repo and must not be edited. It is
  checked by `scripts/generate-duwende-context.sh --check`, which a CI runner cannot run (the source is private) — so it is
  run from `homelab-context`'s `verify-all.sh` on a workstation.

