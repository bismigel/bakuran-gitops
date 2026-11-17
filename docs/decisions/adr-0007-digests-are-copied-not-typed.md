<!-- Mirrored from homelab-context/docs/decisions/ on 2026-11-18. The original is authoritative; if this copy and that one
     disagree, that one is right. It is here because the reasoning is the part of this estate that is hardest to fake, and
     because a reviewer should not have to ask for it. -->

# 0007 — Image digests are copied whole, and CI checks they exist

**Status:** accepted (2026-11-04)

## Context

Three digest slips in one night, all from editing a 71-character string by hand: sabnzbd's padded
out from a 12-character `imageID`, the watchdog's mistyped by one character (`…f6a69` for
`…f9a69`), and the fix producing `@sha256:sha256:…` because a substring was replaced and the
prefix stayed. Each appeared as `ImagePullBackOff` — which on a node whose only egress is the
tunnel is indistinguishable from a network outage.

`check-image-digests.sh` validates *shape*, so all three passed CI.

## Decision

Take a digest **whole** from a source of truth (registry header or an existing manifest) and
replace the entire reference, never a substring. CI asks the registry whether the digest exists
(`HEAD /v2/<repo>/manifests/<digest>`): 404 fails, 401/403/429 are reported as unverified, never
silently passed.

## Consequences

- Malformed-but-well-formed digests now fail in CI instead of at pull time.
- Private images (e.g. `media-mcp` on GHCR) are reported unverified — an honest count, not a pass.
- Registry round trips in CI: 42 references, a few seconds.

## Evidence

`bakuran-gitops#367`; `.github/scripts/verify-image-digests.py`.
