# Sourced by juliet-bootstrap after this extension loads. extension-setup runs
# last, as the `extension` category (juliet-bootstrap --enable=extension).

extension-setup() {
  setup-hey
  setup-zola-mcp
}

# Zola (wedding planning) for Claude Desktop, via the unofficial
# chrischall/zola-mcp server. It's AI-written and unaudited upstream, so it is
# pinned to a tag that was read before use (2026-10-24: only talks to
# *.zola.com; an env-var token is never logged or written to disk). Bumping
# ZOLA_MCP_VERSION means re-auditing — don't track latest, and don't use
# `npx -y zola-mcp`, which runs whatever npm has today.
#
# The build lives in ~/.local/share/zola-mcp (managed, not a dev checkout).
# Claude Desktop runs it through ./zola-mcp/run, which reads the Zola token
# from the OS keychain, so the token never sits in Claude's config file.
ZOLA_MCP_VERSION=v2.1.11
setup-zola-mcp() {
  local dir="$HOME/.local/share/zola-mcp"
  local runner="$EXTENSION_DIR/zola-mcp/run"
  local tool
  for tool in git node npm jq; do
    if ! command -v "$tool" > /dev/null 2>&1; then
      warn "$tool not found — skipping the Zola MCP server."
      return
    fi
  done

  if [[ ! -d "$dir/.git" ]]; then
    spin "Cloning zola-mcp..." git clone --quiet https://github.com/chrischall/zola-mcp.git "$dir" \
      || { bootstrap_error "Failed to clone zola-mcp" "Retry: juliet-bootstrap --enable=extension"; return; }
  elif [[ -n "$(git -C "$dir" status --porcelain --untracked-files=no)" ]]; then
    warn "$dir has local edits — leaving the Zola MCP build alone."
    return
  fi

  if [[ "$(git -C "$dir" describe --tags --exact-match 2> /dev/null)" == "$ZOLA_MCP_VERSION" ]] \
    && [[ -f "$dir/dist/bundle.js" ]]; then
    skip "zola-mcp $ZOLA_MCP_VERSION (already built)"
  else
    # --ignore-scripts: no dependency runs code at install time; the build
    # works without them (esbuild ships its binary as an optional dependency).
    spin "Building zola-mcp $ZOLA_MCP_VERSION..." bash -c '
      set -e
      cd "$1"
      git fetch --quiet --tags
      git -c advice.detachedHead=false checkout --quiet "$2"
      npm ci --ignore-scripts --no-audit --no-fund --silent
      npm run --silent build > /dev/null
    ' _ "$dir" "$ZOLA_MCP_VERSION" \
      || { bootstrap_error "Failed to build zola-mcp" "Rebuild by hand in $dir: npm ci --ignore-scripts && npm run build"; return; }
  fi

  register-zola-mcp "$runner"

  # Only check that a token exists; never read it out.
  local has_token=1
  if is-macos; then
    security find-generic-password -s zola-mcp -a usr > /dev/null 2>&1 || has_token=0
  else
    secret-tool lookup service zola-mcp account usr > /dev/null 2>&1 || has_token=0
  fi
  if ((!has_token)); then
    notice "Zola needs its sign-in token: copy the usr cookie from zola.com (DevTools → Application → Cookies), then run:"
    if is-macos; then
      notice "  security add-generic-password -s zola-mcp -a usr -w"
    else
      notice "  secret-tool store --label='Zola usr cookie' service zola-mcp account usr"
    fi
  fi
}

# Adds mcpServers.zola to Claude Desktop's config, keeping every other key.
# Desktop rewrites this file itself, so it's merged in place, not stowed.
register-zola-mcp() {
  local runner="$1" config
  if is-macos; then
    config="$HOME/Library/Application Support/Claude/claude_desktop_config.json"
  else
    config="$HOME/.config/Claude/claude_desktop_config.json"
  fi
  if [[ ! -d "$(dirname "$config")" ]]; then
    skip "Claude Desktop isn't installed — not registering Zola"
    return
  fi
  [[ -f "$config" ]] || echo '{}' > "$config"

  if [[ "$(jq -r '.mcpServers.zola.command // empty' "$config")" == "$runner" ]]; then
    skip "Zola in Claude Desktop (already registered)"
    return
  fi
  substep "Registering Zola in Claude Desktop..."
  local tmp
  tmp=$(mktemp "$config.XXXXXX")
  cp "$config" "$config.bak"
  if jq --arg cmd "$runner" '.mcpServers = ((.mcpServers // {}) + {zola: {command: $cmd}})' "$config" > "$tmp"; then
    mv "$tmp" "$config"
    notice "Restart Claude Desktop to load Zola (previous config saved to $config.bak)."
  else
    rm -f "$tmp"
    bootstrap_error "Failed to add Zola to $config" "Its JSON may be malformed; the file was left unchanged."
  fi
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
