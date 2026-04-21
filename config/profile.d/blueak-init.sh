#!/usr/bin/env bash
# /etc/profile.d/blueak-init.sh
#
# Runs on every login — acts as an idempotent installer and updater.
# Each section checks before acting, so re-running is always safe and fast.
# Sourced by /etc/zsh/zshenv — MUST NOT exit or use bare 'exit'.
#
# Silent: all output goes only to the log file, never to the terminal.
# Logs to: ~/.local/share/blueak/init.log
# To watch live:        tail -f ~/.local/share/blueak/init.log
# To bump a version:    update the VERSION variable in its section
# To force full re-run: rm ~/.local/share/blueak/.versions

# ── Establish log path before backgrounding ───────────────────────────────────
_BLUEAK_LOG_DIR="$HOME/.local/share/blueak"
_BLUEAK_LOG="$_BLUEAK_LOG_DIR/init.log"
mkdir -p "$_BLUEAK_LOG_DIR"

# ── First login vs subsequent ───────────────────────────────────────────────
_FIRST_RUN_MARKER="$_BLUEAK_LOG_DIR/.first-run-done"
if [[ ! -f "$_FIRST_RUN_MARKER" ]]; then
    # First login: run synchronously, output to both terminal and log
    touch "$_FIRST_RUN_MARKER"
    exec >> >(tee -a "$_BLUEAK_LOG") 2>&1
else
    # Subsequent logins: completely silent, background subshell
    (
    set -uo pipefail

    LOG_DIR="$_BLUEAK_LOG_DIR"
    LOG="$_BLUEAK_LOG"
    VERSION_FILE="$LOG_DIR/.versions"

    mkdir -p "$LOG_DIR" "$HOME/.local/bin" "$HOME/.local/share/applications"

    # Rotate log if over 1 MB
    [[ -f "$LOG" ]] && [[ $(stat -c%s "$LOG" 2>/dev/null || echo 0) -gt 1048576 ]] \
        && mv "$LOG" "${LOG}.old"

    exec >> "$LOG" 2>&1

    echo ""
    echo "════════════════════════════════════════"
    echo "[blueak-init] $(date '+%Y-%m-%d %H:%M:%S') — login init"
    echo "════════════════════════════════════════"

    ########################################
    # HELPERS
    ########################################

log()  { echo "➜  $1"; }
ok()   { echo "✔  $1"; }
warn() { echo "!  $1"; }

get_version() {
    grep "^${1}=" "$VERSION_FILE" 2>/dev/null | cut -d= -f2 || echo ""
}

set_version() {
    touch "$VERSION_FILE"
    if grep -q "^${1}=" "$VERSION_FILE" 2>/dev/null; then
        sed -i "s|^${1}=.*|${1}=${2}|" "$VERSION_FILE"
    else
        echo "${1}=${2}" >> "$VERSION_FILE"
    fi
}

# Copy a file from /etc/skel if missing or changed since last image update.
skel_copy() {
    local src="/etc/skel/$1"
    local dest="$HOME/$1"
    mkdir -p "$(dirname "$dest")"
    if [[ ! -f "$src" ]]; then
        warn "skel: $src not found — skipping"
        return 1
    fi
    if [[ ! -f "$dest" ]] || ! cmp -s "$src" "$dest"; then
        cp "$src" "$dest" \
            && ok "skel: copied $1" \
            || warn "skel: failed to copy $1"
    else
        ok "skel: $1 (up to date)"
    fi
}

########################################
# BREW HELPERS
########################################

require_brew() { command -v brew &>/dev/null; }

brew_ensure() {
    local pkg="$1" flag="${2:-}"
    if [[ "$flag" == "--cask" ]]; then
        brew list --cask "$pkg" &>/dev/null 2>&1 \
            && ok "brew cask: $pkg (present)" \
            || { log "brew cask: installing $pkg...";
                 brew install --cask "$pkg" 2>/dev/null \
                     && ok "brew cask: $pkg installed" \
                     || warn "brew cask: $pkg failed (non-fatal)"; }
    else
        brew list --formula "$pkg" &>/dev/null 2>&1 \
            && ok "brew: $pkg (present)" \
            || { log "brew: installing $pkg...";
                 brew install "$pkg" 2>/dev/null \
                     && ok "brew: $pkg installed" \
                     || warn "brew: $pkg failed (non-fatal)"; }
    fi
}

########################################
# 1. HOMEBREW PACKAGES
########################################

log "--- Homebrew packages ---"

if ! require_brew; then
    warn "Homebrew not found — skipping brew packages"
    warn "Install it with: /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
else
    for pkg in lazygit git-delta gh gitleaks; do brew_ensure "$pkg"; done
    for pkg in atuin tmux tldr; do brew_ensure "$pkg"; done
    for pkg in jq yq xh; do brew_ensure "$pkg"; done
    for pkg in trivy grype; do brew_ensure "$pkg"; done
    for pkg in yazi duf dust age; do brew_ensure "$pkg"; done
    brew_ensure "font-meslo-lg-nerd-font" --cask
fi

########################################
# 2. FLATPAK
########################################

log "--- Flatpak ---"

flatpak remote-add --user --if-not-exists flathub \
    https://dl.flathub.org/repo/flathub.flatpakrepo 2>/dev/null \
    && ok "flathub remote present" \
    || warn "flathub remote-add failed"

if ! flatpak list --user --app 2>/dev/null | grep -q "com.1password.1Password"; then
    log "Installing 1Password..."
    flatpak install --user -y flathub com.1password.1Password 2>/dev/null \
        && ok "1Password installed" \
        || warn "1Password install failed (non-fatal)"
else
    ok "1Password present"
fi

########################################
# 3. NYXT BROWSER
# Baked into the image as an AppImage at /usr/bin/nyxt.
#
# Handles both new and existing users:
#   - Removes old flatpak install if present
#   - Seeds themes directory + set-nyxt-theme script
#   - Applies default theme (eldritch) if none set
#   - Updates theme.lisp when image ships changes
#   - Registers .desktop + MIME types
########################################

log "--- Nyxt ---"

# ── Migration: remove old flatpak Nyxt if present ────────────────────────────
if flatpak list --user --app 2>/dev/null | grep -q "org.nyxt.Nyxt"; then
    log "Nyxt: removing old flatpak install..."
    flatpak uninstall --user -y org.nyxt.Nyxt 2>/dev/null \
        && ok "Nyxt: flatpak removed" \
        || warn "Nyxt: flatpak removal failed (non-fatal)"
fi

# ── Seed Nyxt config (overwrite to propagate theme changes) ─────────────────
skel_copy ".config/nyxt/config.lisp"

# ── Seed themes directory ───────────────────────────────────────────────────
THEMES_DIR="$HOME/.config/nyxt/themes"
mkdir -p "$THEMES_DIR"
for theme_src in /etc/skel/.config/nyxt/themes/*.json; do
    if [[ -f "$theme_src" ]]; then
        theme_name=$(basename "$theme_src")
        if [[ ! -f "$THEMES_DIR/$theme_name" ]] || ! cmp -s "$theme_src" "$THEMES_DIR/$theme_name"; then
            cp "$theme_src" "$THEMES_DIR/$theme_name" \
                && ok "Nyxt: theme $theme_name seeded" \
                || warn "Nyxt: failed to seed theme $theme_name"
        fi
    fi
done

# ── Seed set-nyxt-theme script ────────────────────────────────────────────────
if [[ ! -f "$HOME/.local/bin/set-nyxt-theme" ]] || \
   ! cmp -s /etc/skel/.local/bin/set-nyxt-theme "$HOME/.local/bin/set-nyxt-theme" 2>/dev/null; then
    mkdir -p "$HOME/.local/bin"
    cp /etc/skel/.local/bin/set-nyxt-theme "$HOME/.local/bin/set-nyxt-theme" \
        && chmod +x "$HOME/.local/bin/set-nyxt-theme" \
        && ok "Nyxt: set-nyxt-theme script installed" \
        || warn "Nyxt: set-nyxt-theme script install failed"
fi

# ── Apply default theme (noctalia — live syncs with Noctalia-gtk daemon) ──
NYXT_THEME_MARKER="$THEMES_DIR/current"
if [[ ! -f "$NYXT_THEME_MARKER" ]]; then
    if command -v set-nyxt-theme &>/dev/null; then
        set-nyxt-theme noctalia && ok "Nyxt: default theme (noctalia) applied — syncs with Noctalia-gtk"
    elif [[ -f "$HOME/.local/bin/set-nyxt-theme" ]]; then
        python3 "$HOME/.local/bin/set-nyxt-theme" noctalia && ok "Nyxt: default theme (noctalia) applied — syncs with Noctalia-gtk"
    fi
fi

# ── Register .desktop entry for launcher ─────────────────────────────────────
NYXT_DESKTOP_SRC="/usr/share/applications/nyxt.desktop"
NYXT_DESKTOP_USR="$HOME/.local/share/applications/nyxt.desktop"
if [[ -f "$NYXT_DESKTOP_SRC" ]]; then
    if [[ ! -f "$NYXT_DESKTOP_USR" ]] || ! cmp -s "$NYXT_DESKTOP_SRC" "$NYXT_DESKTOP_USR"; then
        cp "$NYXT_DESKTOP_SRC" "$NYXT_DESKTOP_USR" \
            && ok "Nyxt: .desktop entry installed" \
            || warn "Nyxt: .desktop install failed"
    else
        ok "Nyxt: .desktop entry up to date"
    fi
else
    warn "Nyxt: /usr/share/applications/nyxt.desktop not found — launcher registration skipped"
fi

# ── Refresh desktop database so launcher picks up the entry ──────────────────
if command -v update-desktop-database &>/dev/null; then
    update-desktop-database "$HOME/.local/share/applications/" 2>/dev/null \
        && ok "Nyxt: desktop database refreshed" \
        || warn "Nyxt: desktop database refresh failed (non-fatal)"
fi

########################################
# 4. TAG-BASED FILE BROWSER
########################################

log "--- AkTags Daemon ---"
mkdir -p ~/.config/systemd/user ~/.local/bin
ln -sf /usr/bin/aktags ~/.local/bin/aktags 2>/dev/null || true
skel_copy ".config/systemd/user/aktags-daemon.service"
systemctl --user daemon-reload 2>/dev/null || true
if ! systemctl --user is-enabled aktags-daemon &>/dev/null 2>&1; then
    systemctl --user enable --now aktags-daemon 2>/dev/null \
        && ok "AkTags daemon enabled" \
        || warn "AkTags daemon failed"
else
    ok "AkTags daemon enabled"
fi

xdg-mime default aktags.desktop inode/directory 2>/dev/null || true

########################################
# 5. NOCTALIA-GTK (GTK theme sync)
########################################

log "--- Noctalia GTK Theme Sync ---"
ln -sf /usr/local/bin/noctalia-gtk ~/.local/bin/noctalia-gtk 2>/dev/null || true
skel_copy ".config/systemd/user/noctalia-gtk.service"
systemctl --user daemon-reload 2>/dev/null || true
if ! systemctl --user is-enabled noctalia-gtk &>/dev/null 2>&1; then
    systemctl --user enable --now noctalia-gtk 2>/dev/null \
        && ok "Noctalia GTK daemon enabled" \
        || warn "Noctalia GTK daemon failed"
else
    ok "Noctalia GTK daemon enabled"
fi

########################################
# 6. CAC SETUP
########################################

log "--- CAC setup ---"

if [[ ! -f "$HOME/.pki/nssdb/cert9.db" ]]; then
    mkdir -p "$HOME/.pki/nssdb"
    certutil -d sql:"$HOME/.pki/nssdb" -N --empty-password 2>/dev/null \
        && ok "NSS database created" \
        || warn "certutil not available — NSS DB not created"
else
    ok "NSS database present"
fi

SCDAEMON_CONF="$HOME/.gnupg/scdaemon.conf"
mkdir -p "$HOME/.gnupg" && chmod 700 "$HOME/.gnupg"
if ! grep -q "disable-ccid" "$SCDAEMON_CONF" 2>/dev/null; then
    echo "disable-ccid" >> "$SCDAEMON_CONF"
    gpgconf --kill scdaemon 2>/dev/null || true
    ok "scdaemon CCID disabled"
else
    ok "scdaemon configured"
fi

########################################
# DONE
########################################

    echo ""
    ok "blueak-init complete — $(date '+%H:%M:%S')"

    ) &
    disown 2>/dev/null || true

    return 0 2>/dev/null || true
fi