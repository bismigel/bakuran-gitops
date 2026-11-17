<!-- Mirrored from homelab-context/docs/decisions/ on 2026-11-18. The original is authoritative; if this copy and that one
     disagree, that one is right. It is here because the reasoning is the part of this estate that is hardest to fake, and
     because a reviewer should not have to ask for it. -->

# ADR 0019 — A command that runs on a host is built by the host's repository

**Status:** accepted, 2026-11-18. The move it describes is story 11.17.

## Context

ADR 0016 put executable code in Go and every command in `homelab-context`. Two of those commands are now ports of guards that run
**on a host**, inside a systemd unit:

| command | the unit that wants it |
|---|---|
| `preflight-wg` | run by hand before a deploy (13 documents name it) |
| `verify-backup-copies` | `modules/backup-verify.nix`, weekly, `SuccessExitStatus = [0 1]` |

Neither can be wired, and the reason was measured rather than assumed:

- `modules/backup-verify.nix` does `exec ${pkgs.bash}/bin/bash ${../scripts/verify-backup-copies.sh}`. To exec a Go binary it needs
  `inputs.homelab-context`, and `bakuran-infra` has **no such input**;
- adding it needs a fetchable URL, and there is none: `nix flake metadata git+https://git.bismigel.dev/bismigel/homelab-context`
  fails — the hostname is behind Cloudflare Access (`error: Failed to fetch git repository`), and Forgejo exposes **no SSH service**
  (port 3000 only; `kubectl -n forgejo get svc` has no ssh endpoint), so `git+ssh` is not an alternative;
- making it fetchable would mean publishing the repository or putting an Access service token inside every build, which is a larger
  change than the problem.

`deploy-rs` builds on the deployer and copies closures (no `remoteBuild` in the flake), so a private input would only need credentials on
the workstation — that is the one part of the objection that does *not* hold, and it is worth writing down so the next reader does not
re-litigate it.

## Decision

A Go command belongs to the repository that **builds the closure it runs inside**.

- **`bakuran-infra`** owns commands that a host executes: anything a systemd unit, a timer, or an activation script invokes. Its flake
  builds them (`packages.<system>.<name>`), so `lib.getExe self.packages.${system}.<name>` resolves with no cross-repository fetch.
- **`homelab-context`** owns commands a person or a CI job runs against the estate: checks, readers, renderers, generators. It has no
  systemd units and never needs to be inside a host's closure.

Both repositories use the ADR 0016 layout (`cmd/<binary>`, `internal/<domain>`, no `pkg/`), so the move is a file move plus a flake
package rather than a rewrite.

## Consequences

- `bakuran-infra` gains a `go.mod`, `cmd/`, `internal/` and a `buildGoModule` output. Its CI already has Go, so `go test ./...` becomes
  available there — which it was not before.
- `preflight-wg` and `verify-backup-copies` **move** rather than being copied: two implementations of one guard is the arrangement this
  estate's ADR 0011 exists to prevent, and the differentials travel with them (one against the live node, one in five directions on a
  fixture).
- A command's home is decided by **where it runs**, not by what it is about. `verify-backup-copies` is about backups, which is
  `homelab-context`'s subject — and it still belongs to `bakuran-infra`, because a host runs it at 04:00 with no workstation present.
- The next host-side port (`wg-restore`, `wg-fallback`, `staging/snapshot`, `staging/startvm`, `tunnel-election`, `ansible/run.sh`,
  `homelab-heartbeat` — seven more, ~700 lines) has a home from the start instead of a blocker.

## What was rejected

- **A flake input over a public URL.** It would mean publishing a repository that holds the plan store and the estate's reasoning. The
  cost of that is not the pull request; it is that every internal document becomes a review artefact.
- **An Access service token in the build.** A credential in the build path of every host, to fetch a check. The failure mode is a build
  that cannot run on a machine that has not been given the token, which is exactly the "unfetchable input is worse than a shell script"
  objection that stopped the previous attempt.
- **Vendoring the binary or the source into `bakuran-infra`.** Two copies of one guard, and the copy is the one that drifts — the reason
  the `check-runbook-links` duplicate was deleted rather than kept in sync.
