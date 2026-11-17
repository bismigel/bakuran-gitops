# This repository's own docs

This repository is *desired state*; the reasoning that covers the estate lives in `homelab-context/docs/decisions/`. What is here are
the decisions that make no sense anywhere else — the ones about how *this* repository is arranged.

| document | answers |
|---|---|
| [adr/0001-argocd-ownership.md](adr/0001-argocd-ownership.md) | which ArgoCD objects this repository owns, which it deliberately does not, and why the redis-ha chart needs a post-renderer |

A rule that applies to the estate rather than to this repository belongs in homelab-context, and this page should link it rather than
restate it — a fact with two homes is a fact that drifts. `check-file-refs` in homelab-context resolves every citation in this
repository, and `docs/` is where the ones that cross a repository boundary live with their repository named.
