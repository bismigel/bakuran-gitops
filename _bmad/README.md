# `_bmad/` — BMad configuration for this repository

This repo is a **BMad project at pilot scope**: the planning artifacts are here, the tooling is not.
That is deliberate — see "Why the tooling is absent" below.

Per the framework, `{project-root}` is the nearest folder containing `_bmad/`, which is what this
file establishes for `bakuran-gitops`.

**There is no ticket store here, on purpose.** Work is planned once, in `homelab-context`, because
a change that spans `.81`'s host config, the manifests and the runbook is one piece of work — not
three tickets in three repos that cannot see each other. Each story there names the repository it
lands in with a `repo:` field, and `homelab-context/scripts/check-bmad.py` validates that. What
lives here is the configuration that makes skills work in this directory.

```
config.toml    base layer: project_name, output_folder; active_initiative is empty (no store)
custom/        team overrides (committed); *.user.toml is personal and ignored
scripts/       the three resolvers a skill's activation step calls
```

## Why the tooling is absent

A full BMad install writes ~27 files into `_bmad/scripts` (setup, migrate, roster, knowledge,
render, tests). None of them run unless the BMad *skills* are installed in this project, and here
they are not: the skills live in `homelab-context/.agents/skills`, and this repo is driven by the
same agent session. Keeping the machinery without the caller would be 500 KB of dead weight.

What remains is exactly what a skill needs if it *does* run here:

```console
$ cd _bmad/scripts
$ uv run --no-cache resolve_config.py --project-root ../.. --key core.active_initiative
{ "core.active_initiative": "initiative-argocd-resilience" }
```

`resolve_customization.py` needs `config_utils.py` beside it; together they resolve the
base → team → user layers for either config or a skill's manifest.

## Making it self-contained

```console
$ nix shell nixpkgs#nodejs -c npx -y skills add -g bmad-code-org/BMAD-METHOD --skill bmad -y
$ uv run --no-cache <skill-root>/scripts/setup.py --project-root . --skill <skill-root> --status
```

`setup.py` recreates the full `scripts/` tree and reports what is missing. Prefer the global
(`-g`) scope: the skills are the same in every repo in this estate, and copying them per repo is
1.5 MB each.

## The rule

`_bmad/` holds configuration, `_bmad-output/` holds the plan. Neither holds **facts about the
cluster** — those live in `homelab-context` (`NETWORK.md`, `STORAGE.md`, `STATE.md`) because three
repos sharing one truth beats three repos with three copies of it.
