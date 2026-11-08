# Sourced by juliet-bootstrap after this extension loads. extension-setup runs
# last, as the `extension` category (juliet-bootstrap --enable=extension).

extension-setup() {
  setup-kyle-hey
  setup-kyle-plugin-skills
  setup-kyle-sol
  setup-kyle-flipper-udev
  setup-kyle-zen-profile
  setup-kyle-1password-browsers
  setup-kyle-undms
  setup-kyle-coredump-limits
  setup-kyle-crash-purge
  setup-kyle-duet-webapp
  setup-kyle-rex-keep-claude-rc
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

# Zen moved from the Flathub Flatpak to the COPR build (see DNFfile). The
# Flatpak kept its profiles in ~/.var/app/app.zen_browser.zen/.zen, and the
# native build reads ~/.zen, so copy them over once. Copy, never move: the
# Flatpak's data stays until it's uninstalled by hand. Zen must be closed so
# the copy isn't taken mid-write.
setup-kyle-zen-profile() {
  is-fedora || return 0

  local src="$HOME/.var/app/app.zen_browser.zen/.zen"
  local dest="$HOME/.zen"
  if [[ -e "$dest" ]]; then
    skip "Zen profile (~/.zen exists)"
    return
  fi
  if [[ ! -d "$src" ]]; then
    skip "Zen profile (no Flatpak profile to copy)"
    return
  fi
  if pgrep -x zen >/dev/null || pgrep -x zen-bin >/dev/null; then
    warn "Zen is running: quit it, then re-run juliet-bootstrap --enable=extension to copy its Flatpak profile to ~/.zen"
    return
  fi

  substep "Copying Zen's Flatpak profile to ~/.zen..."
  if ! cp -a "$src" "$dest"; then
    rm -rf "$dest"
    bootstrap_error "Failed to copy $src to $dest" \
      "Quit Zen and copy it manually: cp -a $src $dest"
    return
  fi
  notice "If Zen opens a blank profile, pick your old one in about:profiles"
}

# 1Password for Linux only lets its browser extension use the desktop app
# (unlock with fingerprint/system auth) from browsers it recognizes; Zen isn't
# one, so it goes in this allowlist. 1Password wants the file owned by root,
# and checks it each time a browser connects (no restart needed).
setup-kyle-1password-browsers() {
  is-fedora || return 0

  local src="$EXTENSION_DIR/etc/1password/custom_allowed_browsers"
  local dest=/etc/1password/custom_allowed_browsers
  if cmp -s "$src" "$dest" \
    && [[ "$(stat -c '%U:%G %a' "$dest")" == "root:root 755" ]]; then
    skip "1Password browser allowlist (up to date)"
    return
  fi

  substep "Installing 1Password browser allowlist..."
  if ! sudo install -D -o root -g root -m 755 "$src" "$dest"; then
    bootstrap_error "Failed to install $dest" \
      "Copy it manually: sudo install -D -o root -g root -m 755 $src $dest"
    return
  fi
  notice "Restart Zen if its 1Password extension still asks for your password"
}

# DankMaterialShell (dms) was this machine's niri shell before noctalia, and it
# does not step aside quietly: its user unit is enabled independently of niri's
# spawn-at-startup, and it claims the org.freedesktop.Notifications bus name, so
# leaving it installed means two bars and dms owning notifications. Retire it
# once noctalia (Juliet's shell) is installed.
setup-kyle-undms() {
  is-fedora || return 0

  if ! rpm -q dms &> /dev/null \
    && ! compgen -G "$HOME/.config/systemd/user/*.wants/dms.service" > /dev/null; then
    skip "dms already removed"
    return
  fi

  # Never retire the old shell unless the replacement is actually installed,
  # or a half-bootstrapped machine logs in to a bare compositor.
  if ! rpm -q noctalia &> /dev/null; then
    warn "Keeping dms: noctalia is not installed yet (run the packages step first)."
    return
  fi

  # The unit was enabled by hand via `systemctl --user add-wants niri.service
  # dms.service`, which drops a symlink into niri.service.wants, not the
  # graphical-session.target.wants that [Install] declares. Clear the wants
  # dirs explicitly rather than relying on `disable` to find it.
  if [[ "$(systemctl --user is-enabled dms.service 2> /dev/null)" == enabled ]]; then
    substep "Disabling the dms user service (noctalia is the niri shell)..."
    systemctl --user disable dms.service &> /dev/null \
      || warn "Could not disable dms.service: check systemctl --user status dms.service"
  fi
  rm -f "$HOME"/.config/systemd/user/*.wants/dms.service
  systemctl --user daemon-reload &> /dev/null || true

  if rpm -q dms &> /dev/null; then
    substep "Removing dms (DankMaterialShell)..."
    # cava came in as a dms dependency, but Juliet's DNFfile declares it
    # (noctalia's audio visualizer), so dnf keeps it.
    sudo dnf remove -y dms \
      || bootstrap_error "Failed to remove dms" \
        "Inspect the transaction manually: sudo dnf remove --assumeno dms"
  fi

  if pgrep -x dms &> /dev/null; then
    notice "dms is still running in this session; it goes away at logout (or: systemctl --user stop dms.service)."
  fi
  if [[ -d "$HOME/.config/DankMaterialShell" ]]; then
    notice "Leftover dms config at ~/.config/DankMaterialShell: remove it by hand if you're done with dms."
  fi
}

# Cap how much disk systemd-coredump may use. The drkonqi crash loop (left
# over from the KDE spin) wrote 4.1GB of cores over ten days without anything
# noticing; the stock default (10% of the filesystem) is far too generous to
# act as a warning sign. The caps are in etc/coredump/kyle.conf.
setup-kyle-coredump-limits() {
  is-fedora || return 0

  local src="$EXTENSION_DIR/etc/coredump/kyle.conf"
  local dest=/etc/systemd/coredump.conf.d/kyle.conf
  # Juliet used to install the same caps under its own name.
  local old=/etc/systemd/coredump.conf.d/juliet.conf
  if cmp -s "$src" "$dest" && [[ ! -e "$old" ]]; then
    skip "systemd-coredump caps (up to date)"
    return
  fi

  substep "Capping systemd-coredump disk usage..."
  if ! sudo install -D -m 644 "$src" "$dest"; then
    bootstrap_error "Failed to install $dest" \
      "Copy it manually: sudo install -D -m 644 $src $dest"
    return
  fi
  if [[ -e "$old" ]]; then
    sudo rm -f "$old" || warn "Could not remove the old $old"
  fi
}

# How long crash evidence is worth keeping: long enough to debug something
# from "the other day", short enough that a crash loop can't hoard disk
# between bootstrap runs.
KYLE_CRASH_RETENTION_DAYS=7

# Age-based purge of crash data. setup-kyle-coredump-limits caps
# systemd-coredump's size, but nothing bounded abrt's spool: the drkonqi loop
# left 45 stale reports there. A retention window rather than a one-shot wipe,
# so it stays idempotent.
setup-kyle-crash-purge() {
  is-fedora || return 0

  local stale=0 cores=0
  if [[ -d /var/spool/abrt ]]; then
    stale=$(sudo find /var/spool/abrt -mindepth 1 -maxdepth 1 -type d \
      -mtime +"$KYLE_CRASH_RETENTION_DAYS" 2> /dev/null | wc -l)
  fi
  if [[ -d /var/lib/systemd/coredump ]]; then
    cores=$(find /var/lib/systemd/coredump -type f \
      -mtime +"$KYLE_CRASH_RETENTION_DAYS" 2> /dev/null | wc -l)
  fi
  if (( stale == 0 && cores == 0 )); then
    skip "no crash data older than ${KYLE_CRASH_RETENTION_DAYS}d"
    return
  fi

  if (( stale > 0 )); then
    substep "Purging $stale abrt report(s) older than ${KYLE_CRASH_RETENTION_DAYS}d..."
    sudo find /var/spool/abrt -mindepth 1 -maxdepth 1 -type d \
      -mtime +"$KYLE_CRASH_RETENTION_DAYS" -exec rm -rf {} + \
      || bootstrap_error "Failed to purge the stale abrt spool" \
        "Inspect it manually: sudo du -sh /var/spool/abrt/*"
  fi
  # coredumpctl has no age-based vacuum of its own, so go by the files.
  if (( cores > 0 )); then
    substep "Purging $cores core dump(s) older than ${KYLE_CRASH_RETENTION_DAYS}d..."
    sudo find /var/lib/systemd/coredump -type f \
      -mtime +"$KYLE_CRASH_RETENTION_DAYS" -delete \
      || bootstrap_error "Failed to purge old core dumps" \
        "Inspect them manually: coredumpctl list"
  fi
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
  # The portal folder isn't on XDG_DATA_DIRS under niri, so app launchers
  # (fuzzel) only find the web app through this link.
  local menu_link="$HOME/.local/share/applications/$id.desktop"
  local old_link="$HOME/.local/share/applications/claude-duet.desktop"
  # Inside its sandbox GNOME Web is the only http handler, so it opens other
  # sites' links itself. Hiding that association sends them through the
  # portal to the system default browser (Zen).
  local sandbox_mimeapps="$HOME/.var/app/org.gnome.Epiphany/config/mimeapps.list"
  local wanted_mimeapps="[Removed Associations]
x-scheme-handler/http=org.gnome.Epiphany.desktop;
x-scheme-handler/https=org.gnome.Epiphany.desktop;
text/html=org.gnome.Epiphany.desktop;"
  # Duet opens links through JavaScript, which GNOME Web keeps in the app;
  # this script turns them into plain link clicks, which it sends to Zen.
  local user_js="$EXTENSION_DIR/etc/claude-duet/user-javascript.js"
  local js_schema="org.gnome.Epiphany.web:/org/gnome/epiphany/web-apps/$id/web/"
  # Hides GNOME Web's whole top bar (navigation, menus, window buttons), so
  # the Duet window is just the page. Other GTK apps are untouched.
  local gtk_css="$EXTENSION_DIR/etc/claude-duet/gtk.css"
  local sandbox_gtk_css="$HOME/.var/app/org.gnome.Epiphany/config/gtk-4.0/gtk.css"
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
    && [[ "$(cat "$launcher" 2>/dev/null)" == "$wanted" ]] \
    && [[ "$(readlink "$menu_link")" == "$launcher" ]] \
    && [[ "$(cat "$sandbox_mimeapps" 2>/dev/null)" == "$wanted_mimeapps" ]] \
    && cmp -s "$user_js" "$profile/user-javascript.js" \
    && cmp -s "$gtk_css" "$sandbox_gtk_css" \
    && [[ "$(flatpak run --command=gsettings org.gnome.Epiphany get "$js_schema" enable-user-js 2>/dev/null)" == true ]] \
    && ! [[ -L "$old_link" && ! -e "$old_link" ]]; then
    skip "Claude Duet web app (up to date)"
    return
  fi

  substep "Setting up the Claude Duet web app..."
  if ! { mkdir -p "$profile" "$(dirname "$launcher")" \
    && touch "$profile/.app" \
    && cp "$icon" "$profile/app-icon.png" \
    && printf '%s\n' "$wanted" > "$launcher" \
    && mkdir -p "$(dirname "$menu_link")" \
    && ln -sfn "$launcher" "$menu_link" \
    && mkdir -p "$(dirname "$sandbox_mimeapps")" \
    && printf '%s\n' "$wanted_mimeapps" > "$sandbox_mimeapps" \
    && cp "$user_js" "$profile/user-javascript.js" \
    && flatpak run --command=gsettings org.gnome.Epiphany set "$js_schema" enable-user-js true \
    && mkdir -p "$(dirname "$sandbox_gtk_css")" \
    && cp "$gtk_css" "$sandbox_gtk_css"; }; then
    bootstrap_error "Failed to set up the Claude Duet web app" \
      "Check $profile and $launcher"
  fi
  # Remove the old Chromium launcher's link once its target is gone.
  if [[ -L "$old_link" && ! -e "$old_link" ]]; then
    rm -f "$old_link"
  fi
}

# Keeps `claude rc` alive in the Rex pane labelled claude-rc (session tmp).
# A LaunchAgent runs etc/rex-keep-claude-rc/rex-keep-claude-rc every 60s; the
# script asks rex what's in the pane's foreground and, when claude has exited
# back to the shell, types `claude rc` again (or reopens the tab if it's gone).
# The plist is rendered from a template so it points at $EXTENSION_DIR, then
# (re)loaded only when it changed or isn't loaded. macOS only: Rex is a Mac app.
setup-kyle-rex-keep-claude-rc() {
  is-macos || return 0

  local label=com.kyle.rex-keep-claude-rc
  local src="$EXTENSION_DIR/etc/rex-keep-claude-rc"
  local plist="$HOME/Library/LaunchAgents/$label.plist"
  local domain="gui/$(id -u)"
  local wanted
  wanted=$(sed -e "s#__SCRIPT__#$src/rex-keep-claude-rc#" -e "s#__HOME__#$HOME#g" "$src/$label.plist")

  if [[ -f "$plist" && "$(cat "$plist")" == "$wanted" ]] \
    && launchctl print "$domain/$label" > /dev/null 2>&1; then
    skip "rex claude rc watcher (up to date)"
    return
  fi

  substep "Installing the rex claude rc watcher..."
  mkdir -p "$(dirname "$plist")"
  launchctl bootout "$domain/$label" > /dev/null 2>&1 || true
  printf '%s\n' "$wanted" > "$plist"
  launchctl bootstrap "$domain" "$plist" \
    || bootstrap_error "Failed to load $label" "Try: launchctl bootstrap $domain $plist"
}
