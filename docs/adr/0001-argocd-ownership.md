# ADR 0001: ArgoCD ownership

## Status

Accepted, 2026-10-20.

## Context

ArgoCD was installed from the upstream raw manifests. The platform later tried to
adopt it with the `argo-cd` Helm chart. Two failures followed:

- the Helm chart changed Service selectors to its own label contract, while the
  raw Deployments had different labels, leaving Redis HA services with zero
  endpoints;
- the Helm chart's Deployment selectors were immutable and could not adopt the
  raw Deployments in place.

A self-managed Application with a resource finalizer also cascaded a delete onto
ArgoCD's own Services during a revert.

## Decision

Keep **raw bootstrap ownership, intentionally**.

- Upstream manifests bootstrap ArgoCD.
- `argocd-runtime` manages the existing Deployments, StatefulSets and Services
  from `manifests/argocd/runtime.yaml`.
- ConfigMaps, Secrets, cluster RBAC and NetworkPolicies remain outside that
  Application.
- Redis HA is deferred. ArgoCD uses the single Redis service.

## Consequences

- No Helm release exists for ArgoCD. This is intentional, not missing state.
- A future Helm migration requires a disposable-cluster rehearsal or a complete
  replacement, not an in-place adoption.
- The raw runtime is allowed to be versioned and adopted without immutable-field
  conflicts.
- ArgoCD self-management is limited to the workload layer. Credentials and
  bootstrap behavior stay under explicit human control.

## Rejected alternatives

- Helm `--take-ownership` on the live install: cannot change immutable Deployment
  selectors and would still leave dual ownership during migration.
- Self-managed Helm Application with a finalizer: cascaded deletion risk.
- Redis HA inside ArgoCD: deferred until the label and sentinel failure modes are
  proven in a disposable environment.
