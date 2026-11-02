# Sourced by juliet-bootstrap after this extension loads. extension-setup runs
# last, as the `extension` category (juliet-bootstrap --enable=extension).

extension-setup() {
  setup-kyle-hey
  setup-kyle-plugin-skills
  setup-kyle-sol
  setup-kyle-flipper-udev
  setup-kyle-keyd-dwt-quirk
  setup-kyle-duet-webapp
}

# The HEY CLI ships an agent skill, and the skill is the reason this step
# exists: `hey skill install` copies its SKILL.md to ~/.agents/skills/hey —
# the shared root that opencode and Codex read directly — and links
# ~/.claude/skills/hey for Claude Code, so one install covers all three
# harnesses. The binary is a Brewfile cask on macOS (brew also links the shell
# completions); Fedora has no repo for it, so the vendor installer drops a
# checksum- and signature-verified binary into ~/.local/bin. Nothing here is
# stowed: hey owns its own files (the skill carries a `managed by hey-cli`
# marker and is versioned, so re-running refreshes it after a `hey upgrade`).
setup-kyle-hey() {
  # Resolve first: on Fedora the vendor installer drops the binary in
  # ~/.local/bin, which fish puts on PATH (env.fish) but a bash bootstrap that
  # predates that setup may not have yet.
  local hey_bin
  hey_bin=$(command -v hey 2> /dev/null || true)
  [[ -z "$hey_bin" && -x "$HOME/.local/bin/hey" ]] && hey_bin="$HOME/.local/bin/hey"

  # macOS installs hey from the Brewfile; Fedora has no repo for it, so the
  # vendor installer supplies a checksum- and signature-verified binary (the
  # same shape as setup-poetry).
  if [[ -z "$hey_bin" ]] && is-fedora; then
    spin "Installing hey CLI..." sh -c 'curl -fsSL https://hey.com/install-cli | bash' \
      || bootstrap_error "Failed to install hey" \
        "Retry manually: curl -fsSL https://hey.com/install-cli | bash"
    hey_bin="$HOME/.local/bin/hey"
  fi

  # A selective run that skipped the packages step (macOS) gets a hint rather
  # than a silently missing skill.
  if [[ ! -x "$hey_bin" ]]; then
    warn "hey CLI not found — skipping the HEY agent skill."
    if is-macos; then
      warn "Install it with: brew install --cask basecamp/tap/hey"
      warn "(If brew bundle printed \"Using hey\", a stale hey-desktop cask is shadowing it — brew uninstall --cask hey-desktop first.)"
    else
      warn "Install it with: juliet-bootstrap --enable=extension"
    fi
    return
  fi

  # Homebrew's cask registers the completions system-wide on macOS; the Fedora
  # installer registers them nowhere. hey only rewrites files carrying its own
  # `managed by hey-cli` marker, but compare first anyway (minus that marker
  # line, which install adds) so a current file reads as skipped, not "done". For fish the file lands in
  # Juliet's stowed completions dir, where it is gitignored (hey-cli owns it).
  local completion_file=""
  case "$(basename "${SHELL:-}")" in
    fish) completion_file="$HOME/.config/fish/completions/hey.fish" ;;
    bash) completion_file="$HOME/.local/share/bash-completion/completions/hey" ;;
  esac
  if is-fedora && [[ -n "$completion_file" ]] \
    && [[ -f "$completion_file" ]] \
    && cmp -s <("$hey_bin" shell-completion generate "$(basename "$SHELL")" 2> /dev/null) \
      <(grep -v '^# managed by hey-cli' "$completion_file"); then
    skip "hey shell completions (up to date)"
  elif is-fedora; then
    spin "Installing hey shell completions..." "$hey_bin" shell-completion install \
      || bootstrap_error "Failed to install hey shell completions" \
        "Run manually: hey shell-completion install"
  fi

  # `hey skill` prints the SKILL.md embedded in this binary; install copies it to
  # ~/.agents/skills/hey and links ~/.claude/skills/hey to it.
  if "$hey_bin" skill 2> /dev/null | cmp -s - "$HOME/.agents/skills/hey/SKILL.md" \
    && [[ -L "$HOME/.claude/skills/hey" ]]; then
    skip "HEY agent skill (up to date)"
    return
  fi
  spin "Installing the HEY agent skill..." "$hey_bin" skill install \
    || bootstrap_error "Failed to install the HEY agent skill" \
      "Run manually: hey skill install"
}

# The avegancafe-marketplace plugins (enabled in claude/settings.json) ship
# skills that only Claude Code sees: it loads them from the plugin cache, which
# other harnesses (Raycast AI, opencode, Codex) never look in. This step links
# each skill of every enabled, installed avegancafe plugin into
# ~/.agents/skills, the shared root those harnesses read. Not ~/.claude/skills:
# Claude Code already loads these as plugin skills (`avegancafe:slurp`), so a
# second copy there would list every one twice.
#
# Links point at the installed version's cache dir, so a plugin update leaves
# them on the old version (still on disk) until the next run re-points them.
# Only links into the avegancafe cache count as this step's: a real skill
# folder with the same name is left alone with a warning, and links whose
# skill or plugin has gone are removed. Claude Code installs enabled plugins
# on its first launch, so a fresh machine needs it opened once, then a re-run.
setup-kyle-plugin-skills() {
  local settings="$HOME/.claude/settings.json"
  local installed="$HOME/.claude/plugins/installed_plugins.json"
  local cache="$HOME/.claude/plugins/cache/avegancafe-marketplace"
  local dest="$HOME/.agents/skills"

  if ! command -v jq > /dev/null 2>&1; then
    warn "jq not found — skipping avegancafe plugin skills."
    return
  fi
  if [[ ! -f "$settings" || ! -f "$installed" ]]; then
    skip "avegancafe plugin skills (open Claude Code once to install its plugins, then run juliet-bootstrap --enable=extension)"
    return
  fi

  # One "name<TAB>dir" line per skill to link.
  local wanted="" plugin path skill
  while IFS=$'\t' read -r plugin path; do
    if [[ -z "$path" || ! -d "$path" ]]; then
      warn "$plugin is enabled but not installed — open Claude Code, then run juliet-bootstrap --enable=extension"
      continue
    fi
    for skill in "$path"/skills/*/; do
      [[ -f "$skill/SKILL.md" ]] || continue
      skill="${skill%/}"
      wanted+="$(basename "$skill")"$'\t'"$skill"$'\n'
    done
  done < <(jq -r --slurpfile inst "$installed" '
    (.enabledPlugins // {}) | to_entries[]
    | select(.value == true and (.key | endswith("@avegancafe-marketplace")))
    | "\(.key)\t\((($inst[0].plugins[.key] // [])[0].installPath) // "")"' "$settings")

  mkdir -p "$dest"
  local changed=0 name target link
  while IFS=$'\t' read -r name target; do
    [[ -n "$name" ]] || continue
    link="$dest/$name"
    if [[ -L "$link" && "$(readlink "$link")" == "$target" ]]; then
      continue
    elif [[ -L "$link" && "$(readlink "$link")" == "$cache/"* ]] || [[ ! -e "$link" && ! -L "$link" ]]; then
      ln -sfn "$target" "$link" && changed=$((changed + 1))
    else
      warn "$link already exists and isn't an avegancafe plugin link — leaving it; remove it to link the plugin's $name skill."
    fi
  done <<< "$wanted"

  # Drop this step's links whose skill is no longer wanted (or no longer exists).
  for link in "$dest"/*; do
    [[ -L "$link" && "$(readlink "$link")" == "$cache/"* ]] || continue
    if ! grep -q "^$(basename "$link")"$'\t' <<< "$wanted"; then
      rm "$link" && changed=$((changed + 1))
    fi
  done

  if ((changed)); then
    notice "Linked avegancafe plugin skills into $dest ($changed changed)"
  else
    skip "avegancafe plugin skills (up to date)"
  fi
}

# Sol (ospfranco/sol) is installed by the Brewfile cask. Its portable settings
# live in ~/.config/sol/config.json (runtime state is in state.json beside it),
# but Sol rewrites config.json atomically on every settings change, which would
# replace a stow symlink — so this step merges a tracked seed into it instead.
# The seed's shortcuts map is complete, because Sol uses it in place of its
# defaults rather than on top of them. Sol overwrites config.json while it
# runs, so the step skips until it's quit. SOL_CONFIG_DIR overrides the dir
# (for testing against a copy).
setup-kyle-sol() {
  if ! is-macos; then
    return
  fi
  local dir="${SOL_CONFIG_DIR:-$HOME/.config/sol}"
  local seed="$EXTENSION_DIR/sol/config.seed.json"
  if ! command -v jq > /dev/null 2>&1; then
    warn "jq not found — skipping Sol settings."
    return
  fi
  if pgrep -x sol > /dev/null 2>&1; then
    skip "Sol settings (Sol is running; quit it and run juliet-bootstrap --enable=extension)"
    return
  fi

  substep "Configuring Sol..."
  mkdir -p "$dir"
  [[ -f "$dir/config.json" ]] || echo '{}' > "$dir/config.json"
  local out
  if ! out=$(jq --slurpfile seed "$seed" '. + $seed[0]' "$dir/config.json"); then
    bootstrap_error "Failed to update Sol settings" "Check $dir/config.json is valid JSON, then re-run juliet-bootstrap --enable=extension"
    return
  fi
  if [[ "$out" == "$(jq . "$dir/config.json")" ]]; then
    skip "Sol settings (up to date)"
    return
  fi
  printf '%s\n' "$out" > "$dir/config.json"
  notice "Updated Sol settings"
}

# Flipper Zero serial access for ufbt / qFlipper (Fedora). /dev/ttyACM* is
# root:dialout 0660 and kyle isn't in dialout; a uaccess udev rule grants the
# active seat user an ACL instead, scoped to just the Flipper (serial + DFU).
# macOS needs nothing. Reloading + triggering applies it to a plugged-in
# Flipper; a replug also works.
setup-kyle-flipper-udev() {
  is-fedora || return 0

  local src="$EXTENSION_DIR/etc/udev/42-flipperzero.rules"
  local dest=/etc/udev/rules.d/42-flipperzero.rules
  if cmp -s "$src" "$dest"; then
    skip "Flipper Zero udev rule (up to date)"
    return
  fi

  substep "Installing Flipper Zero udev rule..."
  if ! sudo install -D -m 644 "$src" "$dest"; then
    bootstrap_error "Failed to install $dest" \
      "Copy it manually: sudo install -D -m 644 $src $dest"
    return
  fi
  if sudo udevadm control --reload-rules \
    && sudo udevadm trigger --subsystem-match=tty --subsystem-match=usb; then
    notice "Replug the Flipper if it still can't be opened"
  else
    bootstrap_error "Failed to reload udev rules" \
      "Run: sudo udevadm control --reload-rules, then replug the Flipper"
  fi
}

# keyd (Juliet's dual-role Super key) grabs the laptop keyboard and re-emits
# keys through its own virtual device, which libinput treats as external — so
# niri's disable-while-typing never pauses the touchpad and stray thumb taps
# land mid-typing on the XPS. This quirk marks the keyd keyboard internal.
# libinput reads quirks when a device appears: log out and back in to apply.
setup-kyle-keyd-dwt-quirk() {
  is-fedora || return 0

  local src="$EXTENSION_DIR/etc/libinput/local-overrides.quirks"
  local dest=/etc/libinput/local-overrides.quirks
  if cmp -s "$src" "$dest"; then
    skip "keyd disable-while-typing quirk (up to date)"
    return
  fi

  substep "Installing keyd disable-while-typing libinput quirk..."
  if ! sudo install -D -m 644 "$src" "$dest"; then
    bootstrap_error "Failed to install $dest" \
      "Copy it manually: sudo install -D -m 644 $src $dest"
    return
  fi
  notice "Log out and back in for disable-while-typing to apply"
}

# Claude Duet has no Linux app, so it runs as a GNOME Web (Epiphany Flatpak)
# web app: its own window, and links to other sites open in the default
# browser (Zen). GNOME Web's "Install Site as Web Application" fails on niri
# (the portal install step errors), so this step builds the same thing by
# hand: a profile dir with the `.app` web-app marker and icon, plus the
# launcher in the folder the portal would have written to, which is also
# where GNOME Web looks for it. Sign in to claude.ai once in the new window.
setup-kyle-duet-webapp() {
  is-fedora || return 0

  local id=org.gnome.Epiphany.WebApp_claudeduet
  local profile="$HOME/.var/app/org.gnome.Epiphany/data/$id"
  local launcher="$HOME/.local/share/xdg-desktop-portal/applications/$id.desktop"
  local icon="$EXTENSION_DIR/etc/claude-duet/icon.png"
  local wanted
  wanted="[Desktop Entry]
Type=Application
Name=Claude Duet
Comment=Claude Duet as a GNOME Web app (links to other sites open in the default browser)
Exec=flatpak run --command=epiphany org.gnome.Epiphany --application-mode --profile=$profile https://claude.ai/duet
Icon=$profile/app-icon.png
StartupNotify=true
StartupWMClass=$id
Categories=Network;Chat;
X-Flatpak=org.gnome.Epiphany"

  if [[ -f "$profile/.app" ]] && cmp -s "$icon" "$profile/app-icon.png" \
    && [[ "$(cat "$launcher" 2>/dev/null)" == "$wanted" ]]; then
    skip "Claude Duet web app (up to date)"
    return
  fi

  substep "Setting up the Claude Duet web app..."
  if ! { mkdir -p "$profile" "$(dirname "$launcher")" \
    && touch "$profile/.app" \
    && cp "$icon" "$profile/app-icon.png" \
    && printf '%s\n' "$wanted" > "$launcher"; }; then
    bootstrap_error "Failed to set up the Claude Duet web app" \
      "Check $profile and $launcher"
  fi
}
