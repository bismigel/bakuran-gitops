#!/usr/bin/env python3
"""`manifests/` has one layout, or this fails.

Before 2026-11-15 there were two: fifteen app directories at the top level and five under `manifests/base/`, with no rule about
which an app got. The answer to "where do I add this manifest" was "look at what the last person did".

The rule this enforces:

  manifests/          contains ONLY `base/` and `overlays/`
  manifests/base/<app>  one directory per app group, which is what every Application points at (directly or through an overlay)
  install/            things that are not Kubernetes desired state - today only ArgoCD's own Helm values

Run by `.github/workflows/manifests.yml`. Fails on a stray directory at `manifests/`'s top level, and on any `manifests/<x>`
path that an Application still points at.
"""
import pathlib, re, sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
ALLOWED_TOP = {"base", "overlays"}
problems = []

manifests = ROOT / "manifests"
for p in sorted(manifests.iterdir()):
    if p.is_dir() and p.name not in ALLOWED_TOP:
        problems.append(f"manifests/{p.name}/ is a second layout: app directories belong under manifests/base/")
    elif p.is_file() and p.name != "README.md":
        problems.append(f"manifests/{p.name} sits at the top level; only base/ and overlays/ belong here")

# Every Application must point into base/ (or an overlay that renders base/) - never at a top-level app dir.
for f in sorted((ROOT / "clusters").rglob("*.yaml")):
    for m in re.finditer(r"^\s*path:\s*(manifests/\S+)", f.read_text(), re.M):
        target = m.group(1)
        if not (target.startswith("manifests/base/") or target.startswith("manifests/overlays/")):
            problems.append(f"{f.relative_to(ROOT)}: path {target} is not under manifests/base/ or manifests/overlays/")

if problems:
    print("  Manifest layout:")
    for x in problems:
        print(f"    - {x}")
    sys.exit(1)
top = sorted(p.name for p in manifests.iterdir() if p.is_dir())
apps = sorted(p.name for p in (manifests / "base").iterdir() if p.is_dir())
print(f"  one layout: manifests/{{{','.join(top)}}}, {len(apps)} app group(s) under base/, every Application path points into base/ or overlays/")
