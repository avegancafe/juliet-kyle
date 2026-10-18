#!/usr/bin/env bash
# Move one of Kyle's machines onto the juliet-kyle extension, or undo that.
# Temporary: for the week of 2026-10-18 while each machine is migrated by hand.
#
#   curl -fsSL https://raw.githubusercontent.com/avegancafe/juliet-kyle/main/migrate.sh | bash                    # dry run
#   curl -fsSL https://raw.githubusercontent.com/avegancafe/juliet-kyle/main/migrate.sh | bash -s -- --apply       # migrate
#   curl -fsSL https://raw.githubusercontent.com/avegancafe/juliet-kyle/main/migrate.sh | bash -s -- --revert      # dry run of undo
#   curl -fsSL https://raw.githubusercontent.com/avegancafe/juliet-kyle/main/migrate.sh | bash -s -- --revert --apply
#
# Safety: dry run unless --apply. Stops before changing anything if Juliet has
# uncommitted changes or isn't on main. Backs up every file it edits to
# ~/.config/local/migration-backup-<time>/. Never deletes a directory (moves
# it into the backup instead). Never prints ~/.config/local/.env contents.
# Written for macOS's bash 3.2 too.
set -eu

EXT_URL="https://github.com/avegancafe/juliet-kyle.git"
JULIET="$HOME/.config/Juliet"
LOCAL_DIR="$HOME/.config/local"
ENV_FILE="$LOCAL_DIR/.env"
EXT_DIR="$HOME/.config/juliet-extension"
HEY_FISH="$JULIET/symlinked/config/fish/completions/hey.fish"
HEY_FISH_REL="symlinked/config/fish/completions/hey.fish"

APPLY=false
MODE=migrate
for arg in "$@"; do
  case "$arg" in
    --apply) APPLY=true ;;
    --revert) MODE=revert ;;
    -h | --help) sed -n '2,15p' "$0" 2> /dev/null || true; exit 0 ;;
    *) echo "Unknown option: $arg (use --apply, --revert)" >&2; exit 2 ;;
  esac
done

say() { printf '  %s\n' "$*"; }
step() { printf '\n%s\n' "$*"; }
die() { printf '\nStopped, nothing changed: %s\n' "$*" >&2; exit 1; }
do_or_say() { # do_or_say "description" cmd args...
  local desc="$1"; shift
  if $APPLY; then say "$desc"; "$@"; else say "would: $desc"; fi
}

BACKUP=""
ensure_backup_dir() {
  if [ -z "$BACKUP" ]; then
    BACKUP="$LOCAL_DIR/migration-backup-$(date +%Y%m%d-%H%M%S)"
    (umask 077 && mkdir -p "$BACKUP")
  fi
}
backup() { # backup <file> — copy into this run's backup dir (never printed)
  [ -e "$1" ] || return 0
  ensure_backup_dir
  cp -p "$1" "$BACKUP/"
}

env_has() { [ -f "$ENV_FILE" ] && grep -qE "^$1=" "$ENV_FILE"; }
env_get() { [ -f "$ENV_FILE" ] && sed -nE "s/^$1=(.*)\$/\1/p" "$ENV_FILE" | tail -n 1; }

# Rewrite .env through awk (portable; BSD and GNU sed -i differ), keeping mode 600.
env_rewrite() { # env_rewrite <awk program>
  local tmp
  tmp=$(mktemp "$ENV_FILE.XXXXXX")
  awk "$1" "$ENV_FILE" > "$tmp"
  chmod 600 "$tmp"
  mv -f "$tmp" "$ENV_FILE"
}

set_extension_key() {
  mkdir -p "$LOCAL_DIR"
  if env_has JULIET_EXTENSION; then
    env_rewrite "/^JULIET_EXTENSION=/ { print \"JULIET_EXTENSION=$EXT_URL\"; next } { print }"
  else
    (umask 077 && printf '\nJULIET_EXTENSION=%s\n' "$EXT_URL" >> "$ENV_FILE")
  fi
}

comment_out_key() { # comment_out_key KEY note
  env_rewrite "/^$1=/ { print \"# \" \$0 \"  ($2 $(date +%Y-%m-%d))\"; next } { print }"
}

preflight() {
  [ -d "$JULIET/.git" ] || die "no Juliet checkout at $JULIET."
  local branch dirty
  branch=$(git -C "$JULIET" rev-parse --abbrev-ref HEAD)
  [ "$branch" = "main" ] || die "Juliet is on '$branch', not main. Switch to main first."
  # A modified hey.fish is expected (hey regenerates it) and handled below.
  dirty=$(git -C "$JULIET" status --porcelain --untracked-files=no | grep -v " $HEY_FISH_REL\$" || true)
  [ -z "$dirty" ] || die "Juliet has uncommitted changes:
$dirty
Commit or stash them, then re-run."
}

migrate() {
  step "1. Checking ~/.config/Juliet"
  preflight
  say "clean, on main"

  step "2. Updating Juliet to a version with extension support"
  git -C "$JULIET" fetch -q origin
  if git -C "$JULIET" cat-file -e origin/main:EXTENSIONS.md 2> /dev/null; then
    if [ "$(git -C "$JULIET" rev-parse HEAD)" = "$(git -C "$JULIET" rev-parse origin/main)" ]; then
      say "already up to date"
    else
      git -C "$JULIET" merge-base --is-ancestor HEAD origin/main \
        || die "local main has commits origin/main doesn't. Push or rebase them first."
      # The update untracks hey.fish (hey-cli owns it now). Keep this machine's
      # copy: back it up, let git remove it, then put it back as an ignored file.
      if [ -f "$HEY_FISH" ]; then
        if $APPLY; then
          backup "$HEY_FISH"
          git -C "$JULIET" checkout -q -- "$HEY_FISH_REL" 2> /dev/null || true
          say "set hey.fish aside (restored after the update)"
        else
          say "would: keep hey.fish across the update (backed up, restored after)"
        fi
      fi
      do_or_say "fast-forward Juliet main to origin/main" git -C "$JULIET" merge -q --ff-only origin/main
      if $APPLY && [ -n "$BACKUP" ] && [ -f "$BACKUP/hey.fish" ] && [ ! -e "$HEY_FISH" ]; then
        cp -p "$BACKUP/hey.fish" "$HEY_FISH"
      fi
    fi
  else
    die "origin/main has no extension support yet (no EXTENSIONS.md). Try again after it lands."
  fi

  step "3. Pointing ~/.config/local/.env at juliet-kyle"
  local current
  current=$(env_get JULIET_EXTENSION || true)
  if [ "$current" = "$EXT_URL" ]; then
    say "already set"
  elif [ -n "$current" ]; then
    die "JULIET_EXTENSION is already set to something else ($current). Leaving it alone; fix it by hand if that's wrong."
  else
    $APPLY && backup "$ENV_FILE"
    do_or_say "set JULIET_EXTENSION=$EXT_URL" set_extension_key
  fi
  if env_has JULIET_PERSONAL; then
    do_or_say "comment out the old JULIET_PERSONAL key" comment_out_key JULIET_PERSONAL "replaced by JULIET_EXTENSION"
  fi

  step "4. Loading the extension"
  if [ -e "$EXT_DIR" ] && [ ! -L "$EXT_DIR" ] && [ ! -d "$EXT_DIR/.git" ]; then
    die "$EXT_DIR exists and isn't a clone. Move it aside, then re-run."
  fi
  if $APPLY; then
    if (: < /dev/tty) 2> /dev/null; then
      say "running: juliet-bootstrap --enable=extension"
      bash "$JULIET/bin/juliet-bootstrap" --enable=extension < /dev/tty
    else
      say "no terminal; run this yourself: ~/.config/Juliet/bin/juliet-bootstrap --enable=extension"
    fi
  else
    say "would: run juliet-bootstrap --enable=extension (clones juliet-kyle, links its gitconfig, runs its HEY setup)"
  fi

  finish "Undo with: curl -fsSL https://raw.githubusercontent.com/avegancafe/juliet-kyle/main/migrate.sh | bash -s -- --revert --apply"
}

revert() {
  step "1. Detaching juliet-kyle from ~/.config/local/.env"
  if env_has JULIET_EXTENSION && [ -n "$(env_get JULIET_EXTENSION)" ]; then
    $APPLY && backup "$ENV_FILE"
    do_or_say "comment out JULIET_EXTENSION" comment_out_key JULIET_EXTENSION "reverted by migrate.sh"
  else
    say "not set"
  fi

  step "2. Removing ~/.config/juliet-extension"
  if [ -L "$EXT_DIR" ]; then
    do_or_say "unlink $EXT_DIR" rm "$EXT_DIR"
  elif [ -d "$EXT_DIR" ]; then
    $APPLY && ensure_backup_dir
    do_or_say "move the clone into the backup folder (not deleted)" mv "$EXT_DIR" "${BACKUP:-<backup>}/juliet-extension"
  else
    say "not present"
  fi

  step "3. What stays"
  say "Juliet stays on main. Without the extension this machine no longer gets:"
  say "  github.user=avegancafe (add it to ~/.config/local/gitconfig if you need it),"
  say "  HEY setup, or the personal Brewfile apps (already-installed apps stay installed)."

  finish "Re-migrate with: curl -fsSL https://raw.githubusercontent.com/avegancafe/juliet-kyle/main/migrate.sh | bash -s -- --apply"
}

finish() {
  step "Done$($APPLY || echo " (dry run — nothing changed; add --apply to do it)")."
  [ -n "$BACKUP" ] && say "Backups: $BACKUP"
  say "$1"
}

echo "juliet-kyle migrate.sh — $MODE$($APPLY || echo " (dry run)")"
"$MODE"
