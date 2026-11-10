#!/usr/bin/env python3
"""Scan every image this repo deploys, against the policy in scan-policy.yaml (story 10.4).

Why here and not only in each app repo: those build the images, but *this* repo decides which digest runs. A CVE in a
pinned digest is a property of what is deployed, and the only place that knows the full set is here.

Exit codes: 0 clean (or only accepted findings), 1 policy violated, 2 could not run (reported, never silently passed).
"""
from __future__ import annotations

import datetime
import json
import re
import subprocess
import sys

POLICY = "scripts/scan-policy.yaml"


def load_policy() -> dict:
    import pathlib
    try:
        import yaml
    except ImportError:
        print("  pyyaml missing", file=sys.stderr)
        sys.exit(2)
    return yaml.safe_load(pathlib.Path(POLICY).read_text())


def images() -> list[str]:
    """Every distinct image reference in the manifests, digest and all."""
    out = subprocess.run(["grep", "-rhoE", r"image:[[:space:]]*[^[:space:]]+", "manifests/", "clusters/"],
                         capture_output=True, text=True)
    found = {m.split(None, 1)[1].strip().strip('"\'') for m in out.stdout.splitlines() if m.strip()}
    return sorted(f for f in found if not f.startswith("#"))


def scan(image: str) -> list[dict]:
    """Run trivy, return the findings that matter. A scan that cannot run is an error, not a pass."""
    r = subprocess.run(
        ["trivy", "image", "--quiet", "--format", "json", "--no-progress",
         "--scanners", "vuln", image],
        capture_output=True, text=True,
    )
    if r.returncode not in (0, 1):          # 1 = findings; anything else is a real failure
        print(f"  {image}: scan failed — {r.stderr.strip().splitlines()[-1:] or r.returncode}", file=sys.stderr)
        return []
    if not r.stdout.strip():
        return []
    data = json.loads(r.stdout)
    out = []
    for result in data.get("Results", []):
        for v in result.get("Vulnerabilities") or []:
            out.append({
                "id": v.get("VulnerabilityID"),
                "severity": v.get("Severity", "UNKNOWN"),
                "package": v.get("PkgName"),
                "installed": v.get("InstalledVersion"),
                "fixed": v.get("FixedVersion") or "",
            })
    return out


def main() -> int:
    policy = load_policy()
    fail_on = set(policy.get("fail_on") or [])
    report = set(policy.get("report") or [])
    skip = {s["image"] for s in (policy.get("skip") or [])}
    exceptions = policy.get("exceptions") or []
    today = datetime.date.today()

    refs = images()
    if not refs:
        print("  no images found — is this the gitops repo?", file=sys.stderr)
        return 2
    print(f"  {len(refs)} distinct image references, failing on {sorted(fail_on)}")

    violations, accepted, expired = [], [], []
    for image in refs:
        if image in skip:
            continue
        findings = scan(image)
        for f in findings:
            if f["severity"] not in fail_on | report:
                continue
            match = next((e for e in exceptions
                          if e["id"] == f["id"] and (e.get("image") in (None, image))), None)
            if match:
                exp = match.get("expires")
                if exp and datetime.date.fromisoformat(str(exp)) < today:
                    expired.append((image, f, match))
                else:
                    accepted.append((image, f, match))
                continue
            if f["severity"] in fail_on:
                violations.append((image, f))
            else:
                accepted.append((image, f, None))

    for image, f, match in accepted:
        tag = f"accepted by exception until {match['expires']}" if match else "reported only"
        print(f"  {f['severity']:8} {image.split('@')[0]} {f['id']} ({f['package']}) — {tag}")
    for image, f in violations:
        print(f"  VIOLATION {f['severity']:8} {image.split('@')[0]} {f['id']} ({f['package']} "
              f"{f['installed']} → {f['fixed'] or 'no fix'})")
    for image, f, match in expired:
        print(f"  EXPIRED exception {match['id']} on {image.split('@')[0]} (expired {match['expires']})")

    if violations or expired:
        print(f"  {len(violations)} violation(s), {len(expired)} expired exception(s)")
        return 1
    print("  no policy violations")
    return 0


if __name__ == "__main__":
    sys.exit(main())
