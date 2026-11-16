# A shop window, not a CI system

Since 2026-11-16 the **source of truth is Forgejo** (`git.bismigel.dev`); GitHub receives every push through a push
mirror so the history, the activity graph and the code stay current. Nothing is authored, reviewed or merged here.

CI moved to `.forgejo/workflows/` and runs on a runner inside the homelab cluster. The GitHub workflows were deleted
rather than disabled: the minutes are spent, two CI systems is two places to look (ADR 0011), and a disabled workflow is
one somebody re-enables by accident. They remain in the git history (`git log -- .github/workflows`).

| rule | enforced by |
|---|---|
| never push to `main` | Forgejo protected branch + `hooks/pre-push` |
| every change goes through a PR | Forgejo protected branch |
| checks must pass | `.forgejo/workflows/`, same jobs, same reasons |
