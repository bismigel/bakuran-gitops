# bakuran-gitops

The GitOps repository for a **three-node k3s homelab**: every workload is declared here, and ArgoCD reconciles the cluster to it.
Nothing in this repository is a screenshot of a cluster — it *is* what the cluster runs.

## Why "Bakuran"

Bakuran is Tagalog for the yard or enclosure behind a house, from *bakod*, a
fence. It is the space where things get built, repaired, and occasionally taken
apart to see how they work. This repo is part of that backyard lab: small,
personal, and safe to break on purpose.

## Layout

```
clusters/<cluster>/root.yaml      # app-of-apps, applied once per cluster
clusters/<cluster>/apps/          # one ArgoCD Application per workload
  platform/                       # must exist before workloads
  workloads/                      # the things a human uses
clusters/<cluster>/projects/      # AppProjects: what may deploy where
manifests/base/<component>/       # cluster-agnostic definitions
manifests/overlays/<env>/<c>/     # what one environment changes: placement, storage, refs
```

## How it works

1. `clusters/<cluster>/root.yaml` is applied **once** — the only hand-applied object left.
2. The root reconciles everything under its `apps/` (recursed) **and** the AppProjects in `projects/`.
3. Each Application points at a path here, at an app repo's `deploy/k8s/`, or at a Helm chart; auto-sync and self-heal are on.
4. Sync waves order platform (`"0"`) before workloads (`"1"`).

**Adding a workload** is one file under `clusters/prod/apps/workloads/`.

## Cluster

One **3-node k3s cluster** (embedded etcd), all three schedulable, none tainted:

| node | address | what it runs |
|---|---|---|
| `sitaw-amd` | .82 | ArgoCD, ingress, monitoring, the public sites and APIs, the NFS server, cloudflared |
| `calamansi-intel` | .81 | the media stack (pinned by `nodeSelector`), `/mnt/media`, the WireGuard tunnel |
| `patola-thinkcentre` | .80 | third etcd member, Immich (server, Postgres, Redis) |

The API is a floating address at `192.168.2.100`, held by whichever node wins the lease — losing any one node leaves quorum and a
working API. `.83` is not a member: it is the staging host, running the rehearsal cluster from `clusters/staging/`.

Networking is Cilium VXLAN with **kube-proxy disabled on all three hosts**; every Application targets `https://kubernetes.default.svc`,
so there are no external cluster registrations.

## Edge

The public surface is `*.bismigel.dev` through a **Cloudflare Tunnel** with Zero Trust Access in front of every admin hostname. The
edge itself — DNS, tunnel ingress, Access apps, zone settings — is declared in `bakuran-infra/opentofu/cloudflare/`, not here.

## Secrets

No plaintext secret is in this repository. Machine secrets arrive through **External Secrets** from Bitwarden; the few bootstrap ones
are SOPS-encrypted. A manifest references a Secret; it never contains one.

## Checks

CI runs on the estate's own Forgejo: `yamllint` and digest pinning, the manifest layout and duplicate-object rules, the alert →
runbook links, and an image scan against a baseline that can only shrink. The checks themselves are Go and live in
`homelab-context`; [`docs/CI.md`](docs/CI.md) lists them and what deliberately runs outside CI.

## Where the reasoning lives

Design decisions, incident write-ups and the operational runbook are in `homelab-context` (private) and at
**[bismigel.dev](https://bismigel.dev)**, which is public. This repository holds what the cluster should be; it does not argue for it.
