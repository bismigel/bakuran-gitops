# CI, and why the badge is missing

Every check in this estate runs on **hardware in the house**: a Forgejo instance and a runner pod with a declared toolset. That
repository is behind Cloudflare Access, so the green ticks are not visible from outside — which is why this page exists rather than a
badge.

## What runs on a pull request here

Four jobs, all required. Their names are the ones you would see in the UI, as they appear in the UI:

| job | what fails if it does not hold |
|---|---|
| `checks / validate` | `yamllint` over every manifest; every image reference is pinned by digest |
| `checks / layout` | `manifests/` has one layout, every Application points into it, no object is defined twice, the Prometheus rules parse and the scrape config parses, every alert has an action or a waiver (`check-alert-coverage`), and the generated runbooks are current (`gen-runbooks -check`) |
| `runbook-links / links` | every alert's `runbook_url` resolves to a page *and an anchor* in the published runbook |
| `scan / images` | no new CRITICAL CVE beyond the recorded baseline — the baseline is a ratchet, so a stale entry for an image nobody deploys also fails |

## What runs outside it, and why

| check | where | why not here |
|---|---|---|
| `check-context-bundle` | workstation, via `verify-all` | it generates a ConfigMap from a **private** repository's docs, so a runner here cannot see the source |
| `nix flake check` | workstation | the runner has no nix store; adding nix turns a CI runner into a nix builder, which is its own decision (recorded in the workflow) |
| `verify-image-digests` | by hand | it makes up to three registry requests per image and needs egress to every registry the estate pulls from — a different availability budget from a YAML check |

## The checks themselves

They are **Go** and they live in `homelab-context` (`check-*`, `verify-all`, `scan-images`). Each replaces a shell or Python original
and is verified the same way: same messages, same exit codes, in both the pass and the fail direction.
