# bakuran-gitops — the cluster's desired state

The GitOps repository for a **three-node k3s homelab**: NixOS hosts, one ArgoCD, and every workload declared here rather than applied
by hand. Nothing in this repository is a screenshot of a cluster — it *is* what the cluster reconciles to, and the cluster is
reconciled from it.

### Start here

| if you have | read |
|---|---|
| 2 minutes | the layout below, then `clusters/prod/apps/platform/` — one file per Application |
| 10 minutes | [`docs/adr/0001-argocd-ownership.md`](docs/adr/0001-argocd-ownership.md) — what this repository owns, and what it deliberately does not |
| an hour | the incidents and design notes at **[bismigel.dev](https://bismigel.dev)** — every outage below turned into a post |
| a question | `manifests/base/monitoring/rules/` — the alerts, each with a `runbook_url` that resolves |

### Where the evidence is

Every claim below is checkable: this repository is public and current on both mirrors. The **checks** are Go and live in
`homelab-context` (`check-*`, `verify-all`); the **reasoning** lives there too, in ADRs; and the **incidents** are written up on the
site. What is *not* visible from outside is the CI itself — it runs on the estate's own Forgejo, which is behind Cloudflare Access.
That is a deliberate trade (the estate owns its build hardware), and the cost is that a visitor cannot watch a run; the checks are
therefore described in `docs/` and reproducible with `homelab-context`'s `verify-all`.

> **Origin.** Forgejo ([git.bismigel.dev](https://git.bismigel.dev)) is the source of truth; GitHub receives a push mirror, so what you
> read here is current — but pull requests and CI happen there.


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
are **no external cluster registrations**. Networking is Cilium VXLAN, and
**kube-proxy is disabled on all three hosts** (`--disable-kube-proxy` in each
`hosts/*/default.nix`). This line said "retained" until 2026-11-18: the last stale
sentence in the repository, and the one an outside reviewer caught.

## ArgoCD and Redis

  Redis HA runs three Redis/sentinel pods and three HAProxy pods. The chart
  hardcodes the per-pod announce Services as ClusterIP, so the Helm post-renderer
  `argocd-redis-ha-post-renderer` (Go, in `homelab-context`) makes them headless. Keep it on every
  ArgoCD upgrade. The Redis endpoint is `argocd-redis-ha-haproxy:6379`.

## Edge (Cloudflare)

The edge is declared in **`bakuran-infra/opentofu/cloudflare/`** (OpenTofu): DNS
records, tunnel ingress, Access apps, zone settings and R2 lifecycle, planned and
applied with `tofu` against state in the R2 backend.

`bakuran-infra/cloudflare/sync.sh` was **deleted** on 2026-11-17: it was a second declaration of the same edge, it had drifted
from the accounts it described, and one run would have deleted Forgejo's Access app. The rollback path is `git revert` plus
`tofu apply`. A new hostname means a record in `records_all.tf` **and** an ingress entry
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

Details and the exact commands: `homelab-context/docs/reference/hardening.md`, and runbook 17 for the
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
# (Go command, in homelab-context)
gen-context-bundle --out manifests/base/duwende/context.yaml
```

## What owns what

| directory | what it is | applied by |
|---|---|---|
| `clusters/prod/root.yaml` | the app-of-apps root | ArgoCD, once, by hand |
| `clusters/prod/apps/` | one `Application` per component, in sync waves | the root app |
| `clusters/prod/projects/` | the `prod` AppProject: destinations, `sourceRepos`, cluster-scoped whitelist | the root app |
| `manifests/base/<component>/` | the manifests for a component | its `Application` |
| `manifests/overlays/prod/<component>/` | what differs in production (placement, replicas, patches) | its `Application` |
| — | this repository contains **no scripts**: every check is Go, in `homelab-context`, and runs from there | CI, and `homelab-context`'s `verify-all` |

Two things that catch people out:

- **`clusters/prod/projects/projects.yaml` gates everything.** A new repo needs a `sourceRepos` entry and a new namespace a
  `destinations` entry, or the Application fails to sync with a message that looks like a permissions bug.
- **`manifests/duwende/context.yaml` is generated** from the private `homelab-context` repo and must not be edited. It is
  checked by `check-context-bundle` (Go, in `homelab-context`), which generates it in-process from the private docs and compares — a
  CI runner cannot do that (the source is private), so it runs from `homelab-context`'s `verify-all` on a workstation.

