<!-- Mirrored from homelab-context/docs/decisions/ on 2026-11-18. The original is authoritative; if this copy and that one
     disagree, that one is right. It is here because the reasoning is the part of this estate that is hardest to fake, and
     because a reviewer should not have to ask for it. -->

# 0001 — Every change goes through a PR with green CI

**Status:** accepted (2026-10-29) · **Supersedes:** direct commits to `main`

## Context

Commits landed straight on `main` twice by accident during ordinary work, and a squash-merge
once hit an unrelated PR because the number was passed without checking the branch. Separately,
a change was merged while its CI check was **red** (2026-11-03): `invariants` refused it and
`main` could no longer evaluate, which blocks every later deploy.

## Decision

Work on a branch, open a PR, wait for CI, then `gh pr merge <n> --squash --delete-branch`. Never
merge on red, and always pass *and verify* the PR number.

## Consequences

- A red check is information, not an obstacle. Twice it was right and I was wrong.
- Squash keeps `main` linear, so `git log` reads as a change list.
- The cost is a round trip on every one-line fix. Accepted.

## Evidence

`gh pr checks <n>` before merging; the `validate` workflow in `bakuran-gitops` runs
`kustomize build`, `kubeconform`, `promtool`, duplicate-object and digest checks.

## Enforcement, measured 2026-11-15

GitHub **cannot** enforce this here: branch protection and rulesets on private repositories answer
*"Upgrade to GitHub Pro or make this repository public"* (checked against all three repos; the token is
an owner token with `repo` scope, so it is a plan limit, not a permission one).

What exists instead, and what each is worth:

| guard | catches | bypass |
|---|---|---|
| `hooks/pre-push` (installed by `cmd/install-hooks`) | a push to `main` from this machine, before it leaves | `git push --no-verify` |
| `.github/workflows/guard-main.yml` | a commit on `main` that belongs to no pull request | nothing — it fails the run |
| this ADR | the intention | nothing |

A local hook is a guard against the ordinary mistake, not a security control; the workflow is the
record. On 2026-11-14 a direct push to `main` reached this estate because neither existed. Revisit the
day the plan changes or the repos move to a Forgejo instance, where branch protection is free.
