# Immich HA: why the CNPG cluster is not declared yet

Story 8.2 (homelab-context epic 8). An empty CloudNativePG cluster for Immich was created, failed to
bootstrap, and was removed on 2026-11-05 rather than left half-built. This records the design and the
blocker so the next attempt starts where this one stopped.

## The design, which is not in doubt

- Immich's own Postgres image (`ghcr.io/immich-app/postgres:14-vectorchord0.4.3-pgvectors0.2.0`), because
  the schema has `vector` / `vector(512)` columns and needs `vchord` + `vector`. Postgres 14, not 16.
- `instances: 2`, Longhorn, required anti-affinity — as Forgejo's cluster (8.5) does.
- `bootstrap.initdb.postInitApplicationSQL` creating `vchord`, `vector`, `cube`, `earthdistance`,
  `pg_trgm`, `unaccent`, `uuid-ossp`: the app role is a superuser today (`rolsuper = t`) because Immich
  creates its extensions at startup, and a CNPG bootstrap owner is **not** a superuser.

## The blocker

CNPG's instance manager cannot reach the Kubernetes API server from the `immich` namespace:

```
wait-for-get-cluster: Get "https://10.43.0.1:443/apis/postgresql.cnpg.io/v1/namespaces/immich/clusters/immich-pg":
  dial tcp 10.43.0.1:443: i/o timeout
```

`immich` is default-deny in both directions. Egress rules were added — first `10.43.0.1/32:443`, then the
service CIDR plus the API VIP and the three node addresses on 443/6443 — with the policy correctly selecting
the pods (`cnpg.io/cluster: immich-pg` confirmed on the initdb pod). **The bootstrap still timed out.**
`forgejo` never hit this because it has no NetworkPolicy at all.

## The next thing to test, and why it is probably it

The API server runs in the **host** namespace. Under Cilium, pod → host traffic to `kube-apiserver` is a
separate policy decision from pod → pod, and a plain Kubernetes `NetworkPolicy` cannot express it: it needs
a `CiliumNetworkPolicy` with `toEntities: [kube-apiserver]`. Every other namespace here that allows
`10.43.0.1/32:443` is a namespace whose pods are *not* what the app uses to reach the API (status-api
checks a Service, not the API), which is why the pattern looked sufficient and is not.

So the next attempt is a `CiliumNetworkPolicy` in `immich` granting the CNPG pods `toEntities:
kube-apiserver` — a new CRD pattern in this repository, and one to declare once and reuse.

## Second attempt, 2026-11-05: past the API, stopped at the user

The `CiliumNetworkPolicy` fixed the first blocker — and it is worth recording that the policy *itself* was
invalid at first (`toEntities: [kube-dns]` is rejected by this Cilium, so ArgoCD's sync failed and the object
was never created; the symptom looked exactly like "the policy does not help"). Once valid, CNPG reached the
API server immediately.

Next failure, one layer further down:

```
initdb: could not look up effective user ID 26: user does not exist
```

Measured: the Immich image defines `postgres` at **UID 999**; CNPG's `initdb` expects the user it runs as
(**26**, the Debian `postgres` uid its own images use). The Cluster CRD does not expose a way to override it
— `kubectl explain cluster.postgresql.cnpg.io.spec` has no `securityContext`/`runAsUser` field.

So the remaining work is an image, not a manifest: either
1. a thin derived image `FROM ghcr.io/immich-app/postgres:…` that adds `postgres:x:26` to `/etc/passwd`, or
2. a CNPG-compatible build of the same Postgres with `vchord` + `vector`, from the extensions' upstream
   projects.

Option 1 is smaller and keeps Immich's extension versions exactly, which is what a data-retaining migration
wants. It needs an image build and a place to publish it — which this estate does not have for a one-off
image, hence the open question rather than a half-done attempt.

## What is unchanged

Nothing about Immich itself: `immich-postgres` still runs as a single StatefulSet, the app is untouched,
and the asset data never left it.
