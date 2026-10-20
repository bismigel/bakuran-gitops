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
- requests and memory limits on every container, CPU limits only where the
  workload is request-serving rather than quorum-participating;
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

Every container has a request. Memory limits are universal. CPU limits are on
the ArgoCD components only. Sizing is the 6h cAdvisor peak from this cluster
multiplied by roughly two, so it reflects what these workloads actually do
rather than a copied template:

| workload | peak seen | CPU request | CPU limit | memory request | memory limit |
|---|---|---|---|---|---|
| application-controller | 379 MiB | 100m | 1 | 256 Mi | 1 Gi |
| repo-server | 55 MiB | 100m | 500m | 128 Mi | 512 Mi |
| server | 50 MiB | 100m | 500m | 128 Mi | 512 Mi |
| applicationset-controller | 47 MiB | 50m | 200m | 64 Mi | 256 Mi |
| notifications-controller | 25 MiB | 25m | 100m | 64 Mi | 128 Mi |
| dex-server | 23 MiB | 25m | 100m | 64 Mi | 128 Mi |
| redis | 13 MiB | 50m | none | 64 Mi | 256 Mi |
| sentinel | — | 25m | none | 32 Mi | 128 Mi |
| split-brain-fix | — | 25m | none | 32 Mi | 64 Mi |
| haproxy | 87 MiB | 50m | none | 64 Mi | 192 Mi |

Before this, all 17 pods in the namespace were **BestEffort** — no requests at
all — which makes the whole GitOps control plane the first thing the kubelet
evicts under memory pressure.

## CPU limits and quorum members

Do not put a CPU limit on a Redis, sentinel or split-brain container. The first
attempt did, and the cluster paid for it within the hour:

- redis containers restarted 5–6 times each in 36 minutes across all three
  pods, while sentinel and split-brain-fix containers stayed up;
- every termination was `exitCode: 0, reason: Completed` — a graceful stop, not
  a crash, so the process was being asked to die rather than dying;
- sentinel promoted a new master at 12:54, 12:58 and 13:04;
- `ContainerCPUThrottled` fired on all three `split-brain-fix` containers at
  45–82% of periods against a 100m limit.

Those two facts together are the argument. A CFS quota does not slow a quorum
member politely: it hands it wall-clock delays. Sentinel decides a master is
down by measuring time, so throttling is indistinguishable from failure and
triggers a failover; a restarted replica then looks unhealthy and is restarted
again. Requests still tell the scheduler what the pod costs, and the memory
limit still protects the node — the CPU limit only bought failovers.

The one thing lost is `ContainerCPUThrottled` as a detector for
redis/redis#9956 (sentinel burning a core after a failover). `ContainerHighCPU`
still catches it at 0.8 core for 20 minutes, which is the right shape for that
bug anyway: it is a spin loop, not a throttling problem.

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
