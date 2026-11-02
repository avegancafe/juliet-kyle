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
| `DNFfile` | Personal Fedora packages (Discord, Steam) |
| `Flatpakfile` | Personal Flatpak apps (Zen, Slack, Spotify, GNOME Web for the Claude Duet web app) |
| `claude/settings.json` | Personal Claude Code settings layered over Juliet's: model, effort, theme, output style, plan mode, the avegancafe marketplace and its plugins |
| `home/.config/autostart/claude-duet.desktop` | Fedora login autostart: opens Claude Duet when the session starts (`niri-extension.kdl` puts it on the coding workspace) |
| `home/.config/autostart/org.freedesktop.problems.applet.desktop` | Hides abrt's "Oops!" crash popups at login (abrtd itself keeps running) |
| `home/.config/niri-extension.kdl` | Additions to Juliet's niri config, which includes this file: the "gaming" workspace, Steam at login, and the Steam and Claude Duet window rules |
| `home/.config/mimeapps.list` | Replaces Juliet's: Zen is the default browser |
| `etc/keeb/` | Layouts and VIA definitions for Kyle's keyboards, and Karabiner rules |
| `gitconfig` | `[github] user = avegancafe` |
| `bootstrap.bash` | `extension-setup`: installs the HEY CLI on Fedora, its shell completions, and its agent skill; sets up Claude Duet as a GNOME Web app on Fedora (Claude Duet has no Linux app; links to other sites open in Zen; sign in once in its window); Flipper Zero udev rule; cleanup left over from this machine's KDE-spin and DankMaterialShell days (removes dms, caps core dumps, purges crash data older than 7 days) |
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

## Zola

Zola for Claude lives in [avegancafe/zola-mcp-remote](https://github.com/avegancafe/zola-mcp-remote), a claude.ai connector, so it needs nothing on this machine.
