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
| `bootstrap.bash` | `extension-setup`: installs the HEY CLI on Fedora, its shell completions, and its agent skill; builds the Zola MCP server and registers it in Claude Desktop |
| `zola-mcp/run` | Claude Desktop's launcher for Zola: reads the Zola token from the OS keychain and starts the pinned build |
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

## Zola in Claude Desktop

`setup-zola-mcp` builds the unofficial
[chrischall/zola-mcp](https://github.com/chrischall/zola-mcp) server, pinned to
an audited tag (`ZOLA_MCP_VERSION` in `bootstrap.bash`; bumping it means
re-auditing), into `~/.local/share/zola-mcp`. It then adds it to Claude
Desktop's config. The token stays in the OS keychain, never in a file. Store it
once: copy the `usr` cookie from zola.com (DevTools → Application → Cookies;
it lasts about a year), then run:

```
secret-tool store --label='Zola usr cookie' service zola-mcp account usr   # Fedora
security add-generic-password -s zola-mcp -a usr -w                          # macOS
```

Restart Claude Desktop afterwards. About half the write tools (vendors, budget,
seating, inquiries, invitations, website theme) have no confirmation step of
their own, so leave them on "ask" in Desktop's tool permissions.
