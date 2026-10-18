# juliet-kyle

Kyle's personal layer on top of [Juliet](https://github.com/avegancafe/Juliet):
the apps, accounts and setup steps that are Kyle's taste rather than shared
tooling. It's also the reference example for writing your own extension. See
Juliet's [EXTENSIONS.md](https://github.com/avegancafe/Juliet/blob/main/EXTENSIONS.md)
for what each file does, and start from Juliet's
[`extension-template/`](https://github.com/avegancafe/Juliet/tree/main/extension-template).

## Use

In `~/.config/local/.env` on each machine:

```
JULIET_EXTENSION=https://github.com/avegancafe/juliet-kyle.git
```

then run `juliet-bootstrap`. To run just this extension's setup steps, use
`juliet-bootstrap --enable=extension`.

## What's here

| File | What it does |
|------|--------------|
| `Brewfile` | Personal macOS apps (HEY CLI, Obsidian, Zen, SoundSource, …) and their taps |
| `gitconfig` | `[github] user = avegancafe` |
| `bootstrap.bash` | `extension-setup`: installs the HEY CLI on Fedora, its shell completions, and its agent skill |
| `.env.template` | Keys this setup reads from `~/.config/local/.env`. Blank values only, never secrets |

## Migrating an existing machine (week of 2026-10-18)

`migrate.sh` moves a machine that predates extensions onto this one: it
fast-forwards Juliet, keeps the local `hey.fish`, sets `JULIET_EXTENSION` in
`~/.config/local/.env` (backed up first, never printed), and runs
`juliet-bootstrap --enable=extension`. It's a dry run unless you pass
`--apply`, and it stops without changing anything if Juliet has uncommitted
changes.

```
curl -fsSL https://raw.githubusercontent.com/avegancafe/juliet-kyle/main/migrate.sh | bash
curl -fsSL https://raw.githubusercontent.com/avegancafe/juliet-kyle/main/migrate.sh | bash -s -- --apply
```

`--revert --apply` undoes it: comments out `JULIET_EXTENSION` and moves
`~/.config/juliet-extension` into the backup folder.
