# The CI runner, with its toolset baked in.
#
# WHY THIS EXISTS
#
# The runner installs fifteen packages with `apk add` at container start, and downloads trivy from a release
# tarball. One long-lived pod pays that once (~30 s) and nobody notices. A pod per job pays it *per job*, which
# is why "ephemeral runners" was not worth doing before this image: the tool would have made CI slower than the
# thing it replaced.
#
# This image is therefore the prerequisite for the two changes after it:
#   1. `replicas: N` of `forgejo-runner one-job --ephemeral`, so a job starts in seconds and the pod disappears;
#   2. KEDA's gitea scaler to go 0 -> N on queued jobs and back to 0 when idle.
#
# It also removes a class of bug rather than a delay: `apk add` at start is a network dependency in the boot path
# of every job. A runner that cannot reach Alpine's mirror cannot run CI, which is a strange failure mode for the
# one pod that is supposed to tell you whether things work.
#
# Pinned base: the same digest the Deployment runs today (data.forgejo.org/forgejo/runner:13). A floating tag
# here would mean the toolchain under every job changes without a commit.
FROM data.forgejo.org/forgejo/runner:13@sha256:568cea8c15ddc01fc8f330124892f572af7db37fa28344a2c1914405793bf61d

# Build-time pin for trivy: the manifest used to fetch this at container start, which turned an unpinned scanner
# into a scan that fails on a day nobody changed this repository. Bump it here, in a pull request.
ARG TRIVY_VERSION=0.76.2

USER root

# The toolset, in the order the checks need it:
#   python3 + py3-yaml   yamllint, and every workflow's small scripts
#   go                   the checks are Go (ADR 0016) and one job builds them
#   nodejs               actions/checkout and the other JS actions
#   kustomize            `kubectl kustomize` is how the manifests are rendered before they are validated
#   hugo + pandoc        bismigel-site: org -> markdown -> site
#   kubectl              every check that reads the cluster
#   buildah + netavark   image builds, with --storage-driver vfs (overlay-on-overlay is refused in a container)
#   postgresql16         `scripts/ci-postgres.sh` starts a throwaway server on 127.0.0.1 for the DB tests
#   trivy                the image scan, fetched from its pinned release
#
# Deliberately NOT here, with the reason: kubeconform (no Alpine package; its half is the kustomize render), nix
# (a decision about what the runner's job is, not a package to add).
RUN apk add --no-cache \
        python3 py3-yaml go nodejs yamllint curl jq kustomize hugo pandoc kubectl buildah netavark \
        postgresql16 \
 && curl -sfL "https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}/trivy_${TRIVY_VERSION}_Linux-64bit.tar.gz" \
      | tar -xz -C /usr/local/bin trivy \
 && trivy --version \
 && rm -rf /var/cache/apk/*

# Provenance, printed by the workflow that builds this image: which commit produced the toolchain under every job.
LABEL org.opencontainers.image.title="bakuran CI runner" \
      org.opencontainers.image.description="forgejo-runner 13 + the estate's check toolset, baked in" \
      org.opencontainers.image.source="https://git.bismigel.dev/bismigel/bakuran-gitops" \
      bakuran.dev/trivy-version="${TRIVY_VERSION}"

# The base image's entrypoint (`forgejo-runner`) is what both `daemon` and `one-job` are subcommands of.
# Nothing is overridden on purpose: the manifest decides which one runs.
