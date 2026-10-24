# Sourced by juliet-bootstrap after this extension loads. extension-setup runs
# last, as the `extension` category (juliet-bootstrap --enable=extension).

extension-setup() {
  setup-hey
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
