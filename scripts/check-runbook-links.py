#!/usr/bin/env python3
"""Every alert's runbook_url must point at a page and an anchor that exist.

Why this exists **in this repo**: the alerts are here, the runbook pages are in
`bismigel-site`, and the link between them is a string typed by hand in a YAML annotation.
Until 2026-11-04 the only check lived in `homelab-context`, which cannot gate a pull request
here — so the 71st alert could have arrived with a dead `runbook_url` and nothing would have
failed. That is the gap this closes: the check now runs on the PR that breaks it.

`bismigel-site` is public, so this clones it anonymously and needs no token or secret.

Anchors are derived the way the site's Hugo build derives them: lowercase, drop everything
that is not a letter, digit, space or hyphen, then spaces become hyphens. Org headings are the
source. That derivation was validated against Hugo's real output in `homelab-context` on
2026-11-04 (70 references, 70 resolved, derived set a strict subset of Hugo's ids).

This file is a deliberate copy of `homelab-context/scripts/check-runbook-links.py`, kept
identical in behaviour because that repo is private and CI here cannot read it. If the anchor
derivation changes, change both; the context copy runs the same logic against the real
checkouts every day, so a drift shows up there first.

Usage:
  check-runbook-links.py [--gitops PATH] [--site PATH] [--host URL]
Exit: 0 every reference resolves, 1 something is broken, 2 a repo cannot be read.
"""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

URL_RE = re.compile(r'runbook_url:\s*"?([^"\s]+)"?')
HEADING_RE = re.compile(r"^\*+ (.+)$")


def anchors_for(site: Path) -> dict[str, set[str]]:
    """page-slug -> set of anchors, from `org/runbook/*.org`."""
    pages: dict[str, set[str]] = {}
    org = site / "org" / "runbook"
    if not org.is_dir():
        sys.stderr.write(f"error: {org} not found — is bismigel-site checked out at --site?\n")
        raise SystemExit(2)
    for f in sorted(org.glob("*.org")):
        for line in f.read_text(encoding="utf-8", errors="replace").splitlines():
            m = HEADING_RE.match(line)
            if not m:
                continue
            heading = m.group(1).strip()
            pages.setdefault(f.stem, set()).add(
                re.sub(r"[^a-z0-9 -]", "", heading.lower()).replace(" ", "-"))
    return pages


def references(gitops: Path) -> set[str]:
    manifests = gitops / "manifests"
    if not manifests.is_dir():
        sys.stderr.write(f"error: {manifests} not found\n")
        raise SystemExit(2)
    refs: set[str] = set()
    for f in manifests.rglob("*.yaml"):
        refs.update(URL_RE.findall(f.read_text(encoding="utf-8", errors="replace")))
    return refs


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--gitops", default=".")
    ap.add_argument("--site", default="site")
    ap.add_argument("--host", default="runbook.bismigel.dev")
    args = ap.parse_args()

    pages = anchors_for(Path(args.site))
    refs = references(Path(args.gitops))
    if not refs:
        # An empty set must not read as success: this is the failure mode that let
        # check-prometheus-rules.sh validate nothing for days after a directory moved.
        sys.stderr.write("error: no runbook_url references found — did the manifests move?\n")
        return 2

    pattern = re.compile(rf"https://{re.escape(args.host)}/runbook/([^/#]+)/?(?:#(.+))?$")
    problems: list[str] = []
    checked = 0
    for url in sorted(refs):
        m = pattern.match(url)
        if not m:
            problems.append(f"not a {args.host} runbook URL: {url}")
            continue
        page, anchor = m.group(1), m.group(2)
        if page not in pages:
            problems.append(f"page does not exist: {url}")
            continue
        if anchor:
            checked += 1
            if anchor not in pages[page]:
                problems.append(f"no heading gives #{anchor} on {page}")

    for p in problems:
        print(f"  FAIL {p}", file=sys.stderr)
    print(f"  {len(refs)} runbook_url reference(s); {checked} with an anchor; "
          f"{len(pages)} page(s) parsed; {len(problems)} broken")
    if problems:
        print("\n  Every alert's runbook_url needs a heading in bismigel-site's "
              "org/runbook/*.org before this merges.\n", file=sys.stderr)
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
