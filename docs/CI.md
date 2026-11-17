# CI, and why the badge is missing

Every check in this estate runs on **hardware in the house**: a Forgejo instance and a runner pod with a declared toolset. That
repository is behind Cloudflare Access, so the green ticks are not visible from outside — which is why this page exists rather than a
badge.

## What runs on a pull request here

Four jobs, all required. Their names are the ones you would see in the UI, taken from a real run on 2026-11-17:

| job | what fails if it does not hold |
|---|---|
| `checks / validate` | `yamllint` over every manifest; every image reference is pinned by digest |
| `checks / layout` | `manifests/` has one layout, every Application points into it, no object is defined twice, the Prometheus rules parse and the scrape config parses |
| `runbook-links / links` | every alert's `runbook_url` resolves to a page *and an anchor* in the published runbook |
| `scan / images` | no new CRITICAL CVE beyond the recorded baseline — the baseline is a ratchet, so a stale entry for an image nobody deploys also fails |

## What runs outside it, and why

| check | where | why not here |
|---|---|---|
| `check-context-bundle` | workstation, via `verify-all` | it generates a ConfigMap from a **private** repository's docs, so a runner here cannot see the source |
| `nix flake check` | workstation | the runner has no nix store; adding nix turns a CI runner into a nix builder, which is its own decision (recorded in the workflow) |
| `verify-image-digests` | by hand | it makes up to three registry requests per image and needs egress to every registry the estate pulls from — a different availability budget from a YAML check |

## The checks themselves

They are **Go**, and they live in `homelab-context` (`check-*`, `verify-all`, `scan-images`). Each was ported from a shell or Python
original and carries a differential against it — same messages, same exit codes, in both the pass and the fail direction. Two of them
could not fail before the port. That is the sort of thing this CI is for.
