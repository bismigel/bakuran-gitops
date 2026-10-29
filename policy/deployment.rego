# Policy checks for rendered Kubernetes manifests (conftest / OPA, both free).
#
# Each rule encodes a mistake this lab has actually made, so the gate exists instead
# of a comment nobody re-reads. `import rego.v1` keeps it valid on current conftest
# (v1 syntax: `deny contains msg if { ... }`).
package main

import rego.v1

# 1. Every Deployment must declare resource requests — a BestEffort pod on the node
#    that also holds etcd is the first thing evicted under memory pressure.
deny contains msg if {
	input.kind == "Deployment"
	container := input.spec.template.spec.containers[_]
	not container.resources.requests
	msg := sprintf("%s/%s: container %q has no resource requests", [input.metadata.namespace, input.metadata.name, container.name])
}

# 2. No floating tags. Digest-pinned images are what makes a rollback mean anything.
deny contains msg if {
	input.kind == "Deployment"
	container := input.spec.template.spec.containers[_]
	endswith(container.image, ":latest")
	msg := sprintf("%s/%s: image %q uses :latest", [input.metadata.namespace, input.metadata.name, container.image])
}

# 3. hostPath has to be a deliberate design decision, not an accident.
#
#    It made the "cluster-agnostic" books base unrunnable on staging (2026-10-29),
#    yet the media stack *needs* it: /mnt/media is a 826 GB mergerfs pool that fails
#    closed rather than serving an empty library. So the media namespaces are an
#    explicit, reviewed exception - and a new hostPath anywhere else fails CI.
# books mounts /mnt/media/books the same way - the library *is* the pool. Moving
# those mounts into the prod overlay (so the shared base stays portable) is the
# cleaner end state and is queued in NEXT-STEPS.
allowed_hostpath_namespaces := {"media", "downloads", "default", "books"}

deny contains msg if {
	input.kind == "Deployment"
	volume := input.spec.template.spec.volumes[_]
	volume.hostPath
	not allowed_hostpath_namespaces[input.metadata.namespace]
	msg := sprintf("%s/%s: hostPath volume %q outside the reviewed exceptions (media pool)", [input.metadata.namespace, input.metadata.name, volume.name])
}

# 4. Privileged containers are a review item, not a default.
deny contains msg if {
	input.kind == "Deployment"
	container := input.spec.template.spec.containers[_]
	container.securityContext.privileged == true
	msg := sprintf("%s/%s: container %q is privileged", [input.metadata.namespace, input.metadata.name, container.name])
}
