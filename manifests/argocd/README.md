# ArgoCD runtime manifests

`runtime.yaml` in this directory is reconciled by the `argocd-runtime` Application
(`prune: false`, `selfHeal: true`, `ServerSideApply=true`, `CreateNamespace=false`).

## Read this first: an empty file is a no-op, not "managed"

`runtime.yaml` is currently **empty**. A directory-type Application with an empty
manifest applies nothing and reports `Synced` + `Healthy`. That status means
"nothing to do", not "ArgoCD owns its own runtime". The first time you fill this
file, expect a real diff — the objects have been unmanaged until now.

## The label contract that broke ArgoCD

Four Services in `argocd` select on the redis-ha chart's labels:

```
app=redis-ha-haproxy,release=argocd
app=redis-ha,release=argocd
```

but the pods running in this cluster carry only `app.kubernetes.io/name=...`.
A Service whose selector matches no pod gets **zero endpoints**, and any client
that dials it gets `connection refused`. In practice that meant:

```
failed to list refs: dial tcp 10.43.104.86:6379: connect: connection refused
```

on every Application that needed a cold repo-server fetch — 9 of 30 stuck at
`Sync=Unknown` while the other 21 were served from a warm cache. The same
mismatch empties `argocd-redis-ha`, the three `announce-*` Services and
`argocd-dex-server`.

**Rule:** the pod template labels must be a superset of the Service selector.
When you import upstream manifests, check this before applying them.

## Fixing it once (before the snapshot)

```bash
# haproxy: add the labels the Service actually selects on
kubectl -n argocd patch deploy argocd-redis-ha-haproxy --type=strategic -p '
  spec:
    template:
      metadata:
        labels:
          app: redis-ha-haproxy
          release: argocd'

# redis-ha servers: same idea, per statefulset template
kubectl -n argocd patch sts argocd-redis-ha-server --type=strategic -p '
  spec:
    template:
      metadata:
        labels:
          app: redis-ha
          release: argocd'
```

Verify before moving on — all four should list addresses, not `<none>`:

```bash
kubectl -n argocd get endpoints argocd-redis-ha-haproxy \
  argocd-redis-ha argocd-redis-ha-announce-0 argocd-redis-ha-announce-1 \
  argocd-redis-ha-announce-2
```

Then confirm the stuck Applications resolve (`count by (sync_status) (argocd_app_info)`
should show `Unknown` → 0).

## Taking ownership

Once the workloads are correct, snapshot them — do not hand-write this file:

```bash
./scripts/snapshot-argocd-runtime.sh
kubectl -n argocd annotate application argocd-runtime \
  argocd.argoproj.io/refresh=hard --overwrite
git add manifests/argocd/runtime.yaml && git commit -m "argocd: adopt runtime objects"
```

The generated file lands in this directory, so the next sync reconciles the same
objects that are already running. First sync after adoption should therefore be
a no-op; if it is not, read the diff before letting it proceed.

## Guardrails (do not "fix" these)

- **No `resources-finalizer` on `argocd-runtime`.** The root app prunes, and the
  finalizer cascades that delete onto everything the Application owns — that is
  how the Services disappeared on 19 Oct.
- **`prune: false`.** A chart or file edit must never delete a live control-plane
  object. Drift shows as `OutOfSync`; you delete by hand, deliberately.
- **`configs.cm` / `configs.secret` stay out of this directory.** Admin password,
  SSO and repo credentials are bootstrap-owned; a sync must never rewrite them.
