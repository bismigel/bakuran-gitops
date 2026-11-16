#!/usr/bin/env bash
# Documents that quietly replace each other.
#
# Two manifests with the same kind + namespace + name are not "an extra rule".
# The API server keeps the last one applied, and the file still reads as if both
# exist. That is how `allow-status-api` for qBittorrent in `downloads` disappeared
# when a second policy of the same name was added for SABnzbd (2026-11-02): the
# policy file showed both pods covered, the cluster had one, and status-api's
# qBittorrent check started timing out with no error anywhere.
#
# Scope: every multi-document file under manifests/ and clusters/. Rendered
# overlays are checked by the kustomize step; this one checks what a reviewer reads.
set -euo pipefail

python3 - "$@" <<'PY'
import glob, sys
import yaml

NAMESPACED = {"NetworkPolicy", "ConfigMap", "Secret", "Service", "Deployment",
              "StatefulSet", "DaemonSet", "Job", "CronJob", "ServiceAccount",
              "PersistentVolumeClaim", "Role", "RoleBinding", "Ingress",
              "HorizontalPodAutoscaler", "PodDisruptionBudget", "ExternalSecret",
              "Middleware", "ServersTransport"}

dupes = []
for path in sorted(glob.glob("manifests/**/*.yaml", recursive=True) +
                   glob.glob("clusters/**/*.yaml", recursive=True)):
    try:
        docs = list(yaml.safe_load_all(open(path)))
    except yaml.YAMLError as e:
        print(f"{path}: not parseable, skipped by this check ({e.__class__.__name__})")
        continue
    seen = {}
    for d in docs:
        if not isinstance(d, dict):
            continue
        kind = d.get("kind")
        name = (d.get("metadata") or {}).get("name")
        if not (kind and name):
            continue
        if kind in NAMESPACED:
            ns = (d.get("metadata") or {}).get("namespace") or "<unset>"
            key = (kind, ns, name)
        else:
            key = (kind, "<cluster>", name)
        if key in seen:
            dupes.append((path, key))
        else:
            seen[key] = path

if dupes:
    print("Duplicate kind/namespace/name - the later document replaces the earlier one:\n")
    for path, key in dupes:
        print(f"  {path}: {key[0]} {key[1]}/{key[2]}")
    print("\nGive them distinct names, or merge them into one document with a")
    print("matchExpressions selector. Do not rely on apply order.")
    sys.exit(1)

print("No duplicate kind/namespace/name within any manifest file.")
PY
