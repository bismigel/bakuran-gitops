# Policy checks for rendered Kubernetes manifests (conftest / OPA, both free).
#
# These encode mistakes this lab has already made, so the gate exists instead of a
# comment nobody re-reads.
package main

# 1. Every Deployment must declare resource requests — a BestEffort pod on the node
#    that holds etcd is the first thing evicted under memory pressure.
deny[msg] {
  input.kind == "Deployment"
  not input.spec.template.spec.containers[_].resources.requests
  msg := sprintf("%s/%s: container has no resource requests", [input.metadata.namespace, input.metadata.name])
}

# 2. No floating tags. Digest-pinned images are how a rollback means something.
deny[msg] {
  input.kind == "Deployment"
  c := input.spec.template.spec.containers[_]
  endswith(c.image, ":latest")
  msg := sprintf("%s/%s: image %q uses :latest", [input.metadata.namespace, input.metadata.name, c.image])
}

# 3. hostPath belongs in an overlay, never in a shared base: it made the "cluster
#    agnostic" books base unrunnable on staging (2026-10-29).
deny[msg] {
  input.kind == "Deployment"
  v := input.spec.template.spec.volumes[_]
  v.hostPath
  msg := sprintf("%s/%s: hostPath volume %q in a shared manifest", [input.metadata.namespace, input.metadata.name, v.name])
}

# 4. Privileged containers are a P0 review item, not a default.
deny[msg] {
  input.kind == "Deployment"
  c := input.spec.template.spec.containers[_]
  c.securityContext.privileged == true
  msg := sprintf("%s/%s: privileged container", [input.metadata.namespace, input.metadata.name])
}
