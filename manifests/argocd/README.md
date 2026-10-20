# ArgoCD ownership

ArgoCD is a Helm release:

- release: `argocd`
- chart: `argo-cd` `10.10.5`
- application version: `v3.5.5`
- namespace: `argocd`

The release was adopted in place with:

```bash
helm -n argocd upgrade --install argocd argo/argo-cd \
  --version 10.10.5 -f manifests/argocd/values.yaml \
  --take-ownership --force-conflicts
```

The existing Deployments had immutable selectors from the raw install, so they
were deleted and recreated by Helm. Services, ConfigMaps, secrets and RBAC were
adopted with `--take-ownership`.

## Current values

- single Redis, not HA;
- `configs.cm.create: false`;
- `configs.secret.createSecret: false`;
- `server.insecure: true`;
- two server, repo-server, applicationset and controller replicas;
- ingress on `nginx-admin` at `argocd.bismigel.dev`.

## Ownership rule

Helm owns ArgoCD now. Do not apply raw ArgoCD manifests or hand-patch its
Deployments and Services. Change values in this file and run a Helm upgrade.

Hand-applying part of a chart render is what produced the October incident: a
Service selecting `app=redis-ha-haproxy,release=argocd` over pods that carried
only `app.kubernetes.io/name`. Zero endpoints, nine Applications stuck at
`Sync=Unknown`, hours lost. One owner per object, always.

---

# Redis HA: known deadlock — do not enable

**Status:** reproduced on a disposable three-VM cluster; identical to the
production failure. Production runs single Redis and stays there until the
upstream chart changes.

## Symptom

- `argocd-redis-ha-server-0` sits in `Init:0/1` indefinitely.
- Its `config-init` logs `Could not connect to Redis ...` in a loop.
- `argocd-redis-ha:26379` (sentinel) has **no usable endpoint**.
- The announce endpoint exists (`10.42.4.4:6379`) but connects time out.
- `argocd-redis-ha-haproxy` waits on the same sentinel and never starts.

This is not scheduling, not CNI, not resources. Pods are placed, the network is
healthy, and the failure reproduces on clean nodes.

## Mechanism — a circular bootstrap dependency

1. `config-init` asks the `argocd-redis-ha` Service which Redis is master.
2. Sentinel, which answers that question, runs in the **Redis container of the same pod**.
3. That container cannot start until `config-init` exits successfully.
4. The headless Service only publishes addresses for **Ready** pods, so there is
   nothing to query — and there never will be.

HAProxy's init depends on the same sentinel lookup, so nothing in the StatefulSet
or the Deployment can make progress. First bootstrap deadlocks; a cluster that
already has a master can survive a restart, which is why this looks
intermittent.

## Where the failing logic lives

Not in this repo. It is rendered from upstream `argo-cd` **10.10.5** → the
`redis-ha` subchart → the `argocd-redis-ha-configmap` (`init.sh`,
`haproxy_init.sh`) and consumed as init containers. Anything here can only
change values, not that script.

## The one check that would confirm the mechanism

On the test cluster, with the StatefulSet stuck:

```bash
kubectl -n argocd get svc argocd-redis-ha \
  -o jsonpath='{.spec.publishNotReadyAddresses}{"\n"}'
```

Empty or `false` means the headless Service publishes only Ready pods, and the
deadlock above is structural for a first bootstrap. If it is `true`, the
circularity lies elsewhere in the init script and the next probe is its log
around the sentinel lookup.

## Options considered — none adopted

- **`publishNotReadyAddresses: true` on the headless Service.** Breaks the
  circularity directly. Not exposed by the chart's values, so it needs a
  Kustomize overlay or a Helm post-renderer — infrastructure to maintain for a
  cache.
- **Boot pod-0 alone, then scale up.** Doesn't help: the init waits on the
  Service, not on replica count.
- **`useHostnames` / announce Services.** The announce Services exist and do
  have endpoints, but they point at pods that are not running yet — the same
  circularity, one indirection later.
- **Fork the subchart.** Permanent maintenance cost, and every ArgoCD bump
  re-opens the fork.

## Decision

**Single Redis.** Redis here is a cache and a lock, not a source of truth:
ArgoCD's desired state is in git, its observed state is in the API server.
Losing Redis degrades performance and pauses reconciliation — it does not lose
configuration. Against that, redis-ha costs four extra pods, an HAProxy hop,
and two documented defects: this bootstrap deadlock and the sentinel CPU spin
(redis/redis#9956) that burned a core per pod on this cluster for hours.

**Revisit if:** a later `argo-cd` chart publishes not-ready addresses for the
headless Service, or a real requirement appears that single Redis cannot meet.
Neither is true today.

## If you touch this anyway

- Change `manifests/argocd/values.yaml` and run a Helm upgrade. Nothing else.
- After any upgrade with redis-ha enabled, the gate is endpoints, not pods:

  ```bash
  kubectl -n argocd get endpoints argocd-redis-ha-haproxy \
    argocd-redis-ha argocd-redis-ha-announce-0 \
    argocd-redis-ha-announce-1 argocd-redis-ha-announce-2
  ```

  Every line must show addresses. Any `<none>` means roll back with
  `helm -n argocd rollback argocd` — do not patch by hand.
