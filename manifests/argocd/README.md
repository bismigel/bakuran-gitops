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

- Redis HA with three Redis/sentinel pods and three HAProxy pods;
- headless per-pod announce Services via the post-renderer below;
- control-plane tolerations for the tainted third node;
- requests and limits on every ArgoCD and redis-ha container;
- `configs.cm.create: false`;
- `configs.secret.createSecret: false`;
- `server.insecure: true`;
- two server, repo-server, applicationset and controller replicas;
- ingress on `nginx-admin` at `argocd.bismigel.dev`.

Chart `redis-ha` 4.38.0 hardcodes announce Services as ClusterIP. That makes
sentinel monitor the Service VIP instead of its pod. The fix is a Helm
post-renderer that changes those Services to headless while keeping
`publishNotReadyAddresses: true`.

## Resources

Every container has a request and a limit. Sizing is the 6h cAdvisor peak from
this cluster multiplied by roughly two, so it reflects what these workloads
actually do rather than a copied template:

| workload | peak seen | request | limit |
|---|---|---|---|
| application-controller | 379 MiB | 256 Mi | 1 Gi |
| repo-server | 55 MiB | 128 Mi | 512 Mi |
| server | 50 MiB | 128 Mi | 512 Mi |
| applicationset-controller | 47 MiB | 64 Mi | 256 Mi |
| notifications-controller | 25 MiB | 64 Mi | 128 Mi |
| dex-server | 23 MiB | 64 Mi | 128 Mi |
| redis | 13 MiB | 64 Mi | 256 Mi |
| sentinel | — | 32 Mi | 128 Mi |
| haproxy | 87 MiB | 64 Mi | 192 Mi |

Before this, all 17 pods in the namespace were **BestEffort** — no requests at
all — which makes the whole GitOps control plane the first thing the kubelet
evicts under memory pressure. A 200m CPU limit on the sentinel container is
deliberate: it turns the redis/redis#9956 core burn into a throttled loop that
`ContainerCPUThrottled` reports, instead of a silent core disappearing.

## When a rollout gets stuck

Twice now a Deployment has sat half-rolled for hours while the cluster looked
healthy: the new ReplicaSet's pod crashlooped, the old ReplicaSet kept serving,
so the Service had endpoints and no Application went `Unknown`. Restart-count
alerts fired for the pod, but nothing described the *rollout*.

Detect it:

```bash
kubectl -n argocd rollout status deploy/argocd-server --timeout=5s
kubectl -n argocd get deploy argocd-server \
  -o jsonpath='{.status.conditions[?(@.type=="Progressing")]}{"\n"}'
```

`Progressing=False` for more than 15 minutes now pages via
`DeploymentRolloutStalled`. `kube_deployment_status_replicas_unavailable > 0`
is the second signal — in the October case it was exactly `1`, because the old
ReplicaSet was still supplying the two available replicas.

What the October case looked like: a pod from the rollout-restart ReplicaSet,
`0/1`, 181 restarts over 9 hours, `podIP 10.42.0.1` — the CNI bridge address
rather than a pod address — with `exitCode 143` from its liveness probe.

Remediate in this order, and never by hand-editing the Deployment:

```bash
# 1. let the ReplicaSet replace the pod with a fresh sandbox
kubectl -n argocd delete pod argocd-server-<hash>-<suffix>
kubectl -n argocd rollout status deploy/argocd-server --timeout=5m

# 2. if the replacement fails the same way, the template is bad: roll back
kubectl -n argocd rollout undo deploy/argocd-server
#    then fix manifests/argocd/values.yaml and run the upgrade below
```

A values change that alters the pod template supersedes the stuck ReplicaSet on
its own, which is why the resource PR cleared this one.

## Upgrade

Helm 4 does not accept executable post-renderers. Use Helm 3.17.3.

```bash
helm -n argocd upgrade --install argocd argo/argo-cd \
  --version 10.10.5 -f manifests/argocd/values.yaml \
  --post-renderer ./scripts/argocd-redis-ha-post-renderer.sh \
  --take-ownership --wait --timeout 12m

kubectl -n argocd rollout restart \
  deploy/argocd-repo-server deploy/argocd-server \
  deploy/argocd-applicationset-controller \
  statefulset/argocd-application-controller
```

Rollback path:

```bash
helm -n argocd rollback argocd
```

## Ownership rule

Helm owns ArgoCD now. Do not apply raw ArgoCD manifests or hand-patch its
Deployments and Services. Change values in this file and run a Helm upgrade.
