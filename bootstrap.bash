# Sourced by juliet-bootstrap after this extension loads. extension-setup runs
# last, as the `extension` category (juliet-bootstrap --enable=extension).

extension-setup() {
  setup-hey
  configure-supercmd
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
setup-hey() {
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

# SuperCmd (SuperCmdLabs/SuperCmd) is installed by the Brewfile cask. This step
# seeds a curated subset of its settings rather than stowing them: the app
# rewrites settings.json at runtime, and that file can hold a plaintext AI-key
# fallback, so it never goes in git. Only non-secret keys are merged here; the
# rest (extension prefs, oauth-tokens.json, AI keys) stays app-owned. The app
# overwrites settings.json when it quits, so the step skips while it's running.
# Quicklinks and snippets aren't seeded yet: they come from the Raycast import.
# SUPERCMD_DATA_DIR overrides the data dir (for testing against a copy).
configure-supercmd() {
  if ! is-macos; then
    return
  fi
  local dir="${SUPERCMD_DATA_DIR:-$HOME/Library/Application Support/SuperCmd}"
  local seed="$EXTENSION_DIR/supercmd/settings.seed.json"
  if ! command -v jq > /dev/null 2>&1; then
    warn "jq not found — skipping SuperCmd settings."
    return
  fi
  if [[ ! -f "$dir/settings.json" ]]; then
    skip "SuperCmd settings (launch SuperCmd once so it creates them)"
    return
  fi
  if pgrep -x SuperCmd > /dev/null 2>&1; then
    skip "SuperCmd settings (SuperCmd is running; quit it and run juliet-bootstrap --enable=extension)"
    return
  fi

  substep "Configuring SuperCmd..."
  # baseColor is SuperCmd's only theme knob: Bamboo's background, from
  # Juliet's etc/themes/raycast-bamboo-theme.json.
  # shellcheck disable=SC2016 # $seed is a jq variable
  _supercmd-merge "$dir/settings.json" "SuperCmd settings" \
    --slurpfile seed "$seed" \
    '.globalShortcut = "Command+Control+F15"
     | .baseColor = "#252623"
     | .hyperKey = ((.hyperKey // {}) + {enabled: false})
     | .navigationStyle = "vim"
     | .commandHotkeys = ((.commandHotkeys // {}) + ($seed[0].commandHotkeys // {}))
     | .commandAliases = ((.commandAliases // {}) + ($seed[0].commandAliases // {}))'

  # Kyle's own Raycast extension isn't in the store; SuperCmd loads it from its
  # source checkout. customExtensionFolders is per-machine (settings.local.json).
  local linear_todos="$HOME/workspace/linear-todos/raycast-extension"
  if [[ ! -d "$linear_todos" ]]; then
    skip "linear-todos extension folder (no checkout at $linear_todos)"
    return
  fi
  [[ -f "$dir/settings.local.json" ]] || echo '{}' > "$dir/settings.local.json"
  # shellcheck disable=SC2016 # $a and $folder are jq variables
  _supercmd-merge "$dir/settings.local.json" "SuperCmd extension folders" \
    --arg folder "$linear_todos" \
    '.customExtensionFolders = ((.customExtensionFolders // []) as $a
       | if ($a | index([$folder])) then $a else $a + [$folder] end)'
}

# _supercmd-merge <file> <label> <jq args...> <filter>: apply a jq filter in
# place, reporting "up to date" when it changes nothing. Writes through the
# existing file (cat >) so its mode is kept.
_supercmd-merge() {
  local file="$1" label="$2" out
  shift 2
  if ! out=$(jq "$@" "$file"); then
    bootstrap_error "Failed to update $label" "Check $file is valid JSON, then re-run juliet-bootstrap --enable=extension"
    return
  fi
  if [[ "$out" == "$(jq . "$file")" ]]; then
    skip "$label (up to date)"
    return
  fi
  printf '%s\n' "$out" > "$file"
  notice "Updated $label"
}
