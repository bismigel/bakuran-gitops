# `_bmad/custom/` — team overrides

Layers resolve base → team → user (`_bmad/scripts/config_utils.py`); later wins per key. Put a
file here only to change *how an agent behaves* — facts about the cluster belong in
`homelab-context`'s reference docs, and decisions belong in its `docs/decisions/`.

`*.user.toml` is personal and ignored.

Deeper context for this project stays in `homelab-context`; nothing here duplicates it.
