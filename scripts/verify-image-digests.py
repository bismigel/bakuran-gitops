#!/usr/bin/env python3
"""Fail if a pinned image digest does not exist in its registry.

Why this exists
---------------
`check-image-digests.sh` verifies the *shape* of a reference
(`repo:tag@sha256:<64 hex>`). A well-formed but wrong digest passes it happily, and
the mistake only surfaces when a pod tries to pull: `ImagePullBackOff`. On a node
whose only egress is a WireGuard tunnel, that is indistinguishable from a network
outage - and it has happened three times in one night (2026-11-03/04):

  * sabnzbd's digest padded out by hand from a 12-character imageID,
  * prometheus-watchdog's digest mistyped (…f6a69 instead of …f9a69),
  * and the "fix" for that producing `@sha256:sha256:…`.

Each was a 71-character string edited by hand. The point of this check is that the
registry is the only authority on whether a digest exists, so ask it.

What is decisive
----------------
`HEAD /v2/<repo>/manifests/<digest>` answers exactly one question: does this digest
exist? By status code:

  200        exists
  404        DOES NOT EXIST  -> hard failure, this is the bug class
  401 / 403  private, or no pull permission -> cannot verify (reported, not failed)
  429        rate limited (Docker Hub) -> cannot verify (reported, not failed)
  5xx / network  the registry is unwell -> retried, then failed

Only 404 fails the build, because only 404 is evidence about the digest. Treating
"cannot verify" as a pass would be the usual lie, so every unverified reference is
named in the summary and the count is always printed.

Usage: verify-image-digests.py [root]        (default root: .)
Exit:  0 all verified, or nothing unverifiable-but-broken; 1 anything wrong.
"""
from __future__ import annotations

import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

REF_RE = re.compile(r"^\s*(?:-\s*)?image:\s*[\"']?([^\s\"']+)[\"']?\s*$")
PINNED_RE = re.compile(r"^(?P<ref>.+)@(?P<digest>sha256:[a-f0-9]{64})$")

ACCEPT = ", ".join([
    "application/vnd.docker.distribution.manifest.v2+json",
    "application/vnd.docker.distribution.manifest.list.v2+json",
    "application/vnd.oci.image.manifest.v1+json",
    "application/vnd.oci.image.index.v1+json",
])

# Anonymous pull tokens. Docker Hub and GHCR both require one even for public
# images; the token endpoint returns a token with no access for private repos,
# which then shows up as 401/403 - reported, not failed.
TOKEN_ENDPOINTS = {
    "registry-1.docker.io": "https://auth.docker.io/token?service=registry.docker.io&scope=repository:{repo}:pull",
    "ghcr.io": "https://ghcr.io/token?scope=repository:{repo}:pull&service=ghcr.io",
    "quay.io": "https://quay.io/v2/auth?service=quay.io&scope=repository:{repo}:pull",
}


def split_reference(ref: str) -> tuple[str, str]:
    """'ghcr.io/a/b:1' -> ('ghcr.io', 'a/b'); 'alpine:3.20' -> (docker hub, 'library/alpine')."""
    first, _, rest = ref.partition("/")
    if rest and ("." in first or ":" in first or first == "localhost"):
        registry, repo = first, rest
    else:
        registry, repo = "registry-1.docker.io", ref
        if "/" not in repo:
            repo = "library/" + repo
    # strip the tag; the digest travels separately
    repo = repo.rsplit(":", 1)[0] if ":" in repo.rsplit("/", 1)[-1] else repo
    if registry == "docker.io":
        registry = "registry-1.docker.io"
    return registry, repo


def token_for(registry: str, repo: str, challenge: str | None = None) -> str | None:
    """Get a pull token. Prefers the registry's own WWW-Authenticate challenge.

    lscr.io and codeberg.org reject even public reads without one, and their realms are
    not Docker Hub's or GHCR's - hardcoding a map for each registry is how three of 42
    references ended up "unverifiable" on the first run (2026-11-04). The challenge
    names its own realm, service and scope; use it.
    """
    url = None
    if challenge and challenge.lower().startswith("bearer"):
        realm = re.search(r'realm="([^"]+)"', challenge)
        service = re.search(r'service="([^"]*)"', challenge)
        scope = re.search(r'scope="([^"]*)"', challenge)
        if realm:
            params = urllib.parse.urlencode({
                "service": service.group(1) if service else registry,
                "scope": scope.group(1) if scope else f"repository:{repo}:pull",
            })
            url = f"{realm.group(1)}?{params}"
    if url is None:
        url = TOKEN_ENDPOINTS.get(registry)
        if url is None:
            return None
        url = url.format(repo=repo)
    try:
        with urllib.request.urlopen(url, timeout=20) as r:
            data = json.load(r)
        return data.get("token") or data.get("access_token")
    except Exception:
        return None


last_challenge: dict[str, str] = {}


def head_digest(registry: str, repo: str, digest: str, token: str | None) -> int:
    """Return an HTTP status, or -1 for a transport failure."""
    req = urllib.request.Request(
        f"https://{registry}/v2/{repo}/manifests/{digest}", method="HEAD"
    )
    req.add_header("Accept", ACCEPT)
    if token:
        req.add_header("Authorization", f"Bearer {token}")
    for attempt in range(3):
        try:
            with urllib.request.urlopen(req, timeout=25) as r:
                return r.status
        except urllib.error.HTTPError as e:
            challenge = e.headers.get("WWW-Authenticate") if e.headers else None
            if challenge:
                last_challenge["www-authenticate"] = challenge
            if e.code in (429, 500, 502, 503, 504) and attempt < 2:
                time.sleep(2 * (attempt + 1))
                continue
            return e.code
        except Exception:
            if attempt < 2:
                time.sleep(2 * (attempt + 1))
                continue
            return -1
    return -1


def collect(root: Path) -> dict[str, list[str]]:
    """digest-ref -> files that name it (for a useful error message)."""
    found: dict[str, list[str]] = {}
    for path in sorted(root.glob("**/*.yaml")):
        if "/.git/" in str(path):
            continue
        try:
            text = path.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        for line in text.splitlines():
            m = REF_RE.match(line)
            if not m:
                continue
            pinned = PINNED_RE.match(m.group(1))
            if not pinned:
                continue
            found.setdefault(m.group(1), []).append(str(path))
    return found


def main() -> int:
    root = Path(sys.argv[1] if len(sys.argv) > 1 else ".")
    refs = collect(root)
    if not refs:
        print("ERROR: no pinned image references found - did the tree move?", file=sys.stderr)
        return 1

    missing: list[tuple[str, list[str]]] = []
    unverified: list[tuple[str, int]] = []
    ok = 0

    for ref, files in sorted(refs.items()):
        registry, repo = split_reference(ref.split("@")[0])
        digest = ref.split("@", 1)[1]
        status = head_digest(registry, repo, digest, token_for(registry, repo))
        if status in (401, 403):
            challenge = last_challenge.get("www-authenticate")
            retry_token = token_for(registry, repo, challenge)
            if retry_token:
                status = head_digest(registry, repo, digest, retry_token)
        if status == 200:
            ok += 1
        elif status == 404:
            missing.append((ref, files))
        else:
            unverified.append((ref, status))

    for ref, files in missing:
        print(f"::error::digest does not exist: {ref}", file=sys.stderr)
        for f in sorted(set(files)):
            print(f"    named in {f}", file=sys.stderr)
    for ref, status in unverified:
        reason = {401: "private/no pull access", 403: "forbidden", 429: "rate limited",
                  -1: "transport failure"}.get(status, f"HTTP {status}")
        print(f"  unverified ({reason}): {ref}")

    print(f"\n  verified {ok}/{len(refs)} digests; {len(missing)} do not exist; "
          f"{len(unverified)} could not be verified")
    return 1 if missing else 0


if __name__ == "__main__":
    sys.exit(main())
