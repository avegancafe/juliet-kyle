# Sourced by juliet-bootstrap after this extension loads. extension-setup runs
# last, as the `extension` category (juliet-bootstrap --enable=extension).

extension-setup() {
  setup-hey
  setup-supercmd
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

# SuperCmd (SuperCmdLabs/SuperCmd) is a macOS launcher with no Homebrew cask,
# so this installs it from the GitHub release. It's install-once: the app
# updates itself (electron-updater), so an existing /Applications/SuperCmd.app
# is left alone. The release's latest-mac.yml (electron-updater's own feed)
# lists each zip with its base64 sha512, which is checked before anything
# lands in /Applications, and spctl must accept the unpacked app as notarized.
# curl sets no quarantine attribute, and none is stripped here either. The one manual step is Kyle granting it Accessibility.
setup-supercmd() {
  if ! is-macos; then
    return
  fi
  if [[ -d /Applications/SuperCmd.app ]]; then
    skip "SuperCmd (already installed; it updates itself)"
    return
  fi

  local releases="https://github.com/SuperCmdLabs/SuperCmd/releases"
  local hint="Download the zip for your Mac from $releases/latest and drag SuperCmd.app into /Applications"
  local tmp
  tmp=$(mktemp -d) || {
    bootstrap_error "Failed to create a temp dir for SuperCmd" "$hint"
    return
  }

  if ! spin "Fetching the SuperCmd release feed..." \
    curl -fsSL -o "$tmp/latest-mac.yml" "$releases/latest/download/latest-mac.yml"; then
    bootstrap_error "Failed to fetch SuperCmd's latest-mac.yml" "$hint"
    rm -rf "$tmp"
    return
  fi

  # Each `files:` entry is a `- url:` line followed by its `sha512:`. Apple
  # silicon takes SuperCmd-<v>-arm64-mac.zip; Intel takes SuperCmd-<v>-mac.zip.
  local pattern='^SuperCmd-[0-9.]+-mac\.zip$'
  [[ "$(uname -m)" == arm64 ]] && pattern='^SuperCmd-[0-9.]+-arm64-mac\.zip$'
  local zip="" sha=""
  read -r zip sha < <(awk -v pattern="$pattern" '
    $1 == "-" && $2 == "url:" { url = $3; next }
    $1 == "sha512:" && url ~ pattern { print url, $2; exit }
    $1 == "sha512:" { url = "" }' "$tmp/latest-mac.yml")
  if [[ -z "$zip" || -z "$sha" ]]; then
    bootstrap_error "No zip for $(uname -m) in SuperCmd's latest-mac.yml" "$hint"
    rm -rf "$tmp"
    return
  fi

  # The feed's sha512 is base64 of the raw digest, not hex.
  if ! spin "Downloading $zip..." curl -fsSL -o "$tmp/$zip" "$releases/latest/download/$zip"; then
    bootstrap_error "Failed to download $zip" "$hint"
    rm -rf "$tmp"
    return
  fi
  if [[ "$(shasum -a 512 "$tmp/$zip" | cut -d' ' -f1 | xxd -r -p | base64)" != "$sha" ]]; then
    bootstrap_error "SuperCmd download failed its sha512 check" "$hint"
    rm -rf "$tmp"
    return
  fi

  # ditto keeps the code signature and extended attributes intact.
  if ! spin "Unpacking $zip..." ditto -x -k "$tmp/$zip" "$tmp/unzipped"; then
    bootstrap_error "Failed to unpack $zip" "$hint"
    rm -rf "$tmp"
    return
  fi

  # With no quarantine attribute Gatekeeper never assesses the app on first
  # launch, so ask it here: refuse anything that isn't a notarized Developer ID.
  if ! spctl -a -t exec "$tmp/unzipped/SuperCmd.app" 2> /dev/null; then
    bootstrap_error "SuperCmd failed Gatekeeper's check (spctl -a)" "$hint"
    rm -rf "$tmp"
    return
  fi

  if spin "Installing SuperCmd..." ditto "$tmp/unzipped/SuperCmd.app" /Applications/SuperCmd.app; then
    notice "SuperCmd installed: launch it once and enable it in System Settings → Privacy & Security → Accessibility."
  else
    bootstrap_error "Failed to install SuperCmd into /Applications" "$hint"
  fi
  rm -rf "$tmp"
}
