# This repository's own docs

This repository is *desired state*; the reasoning that covers the estate lives in `homelab-context/docs/decisions/`. What is here are
the decisions that make no sense anywhere else — the ones about how *this* repository is arranged.

| document | answers |
|---|---|
| [adr/0001-argocd-ownership.md](adr/0001-argocd-ownership.md) | which ArgoCD objects this repository owns, which it deliberately does not, and why the redis-ha chart needs a post-renderer |

A rule that applies to the estate rather than to this repository belongs in homelab-context, and this page should link it rather than
restate it — a fact with two homes is a fact that drifts. `check-file-refs` in homelab-context resolves every citation in this
repository, and `docs/` is where the ones that cross a repository boundary live with their repository named.

## Five decisions, mirrored from the private repository

The reasoning lives in `homelab-context` (private, because it holds the plan store and the operational detail). These five are copied
here because a reviewer should be able to read the judgement without asking for access. Each file says at the top that the original is
authoritative.

| decision | what it settles |
|---|---|
| [0001](decisions/adr-0001-pr-only-change-flow.md) | every change goes through a pull request, and the repository enforces it instead of asking |
| [0002](decisions/adr-0002-never-delete-stateful-objects.md) | PVCs, PVs and Namespaces are never deleted — and what the one exception costs |
| [0007](decisions/adr-0007-digests-are-copied-not-typed.md) | image digests are copied whole, never typed; CI checks they exist in the registry |
| [0018](decisions/adr-0018-the-alert-lifecycle-has-two-folders.md) | an alert rule and a procedure are different objects, and seventy-two generated templates were one too many |
| [0019](decisions/adr-0019-host-side-commands-live-where-they-run.md) | a command belongs to the repository that builds the closure it runs inside |
