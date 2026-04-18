#!/usr/bin/env bash
# /etc/profile.d/blueak-init.sh
#
# Runs on every login — acts as an idempotent installer and updater.
# Each section checks before acting, so re-running is always safe and fast.
# Sourced by /etc/zsh/zshenv — MUST NOT exit or use bare 'exit'.
#
# Logs to: ~/.local/share/blueak/init.log
# To bump a package version: update the VERSION variable in its section.
# To force full re-run:       rm ~/.local/share/blueak/.versions

# ── Run in subshell so sourcing shell is never affected by errors ─────────────
(
set -uo pipefail

########################################
# PATHS
########################################

LOG_DIR="$HOME/.local/share/blueak"
LOG="$LOG_DIR/init.log"
VERSION_FILE="$LOG_DIR/.versions"   # tracks installed versions for update checks

mkdir -p "$LOG_DIR" "$HOME/.local/bin" "$HOME/.local/share/applications"

# Rotate log if over 1MB to prevent unbounded growth
[[ -f "$LOG" ]] && [[ $(stat -c%s "$LOG" 2>/dev/null || echo 0) -gt 1048576 ]] \
    && mv "$LOG" "${LOG}.old"

exec > >(tee -a "$LOG") 2>&1
echo ""
echo "════════════════════════════════════════"
echo "[blueak-init] $(date '+%Y-%m-%d %H:%M:%S') — login init"
echo "════════════════════════════════════════"

########################################
# COLORS
########################################

if [[ -t 1 ]]; then
    GREEN="\033[32m"; BLUE="\033[34m"
    YELLOW="\033[33m"; RESET="\033[0m"
else
    GREEN=""; BLUE=""; YELLOW=""; RESET=""
fi

log()  { echo -e "${BLUE}➜${RESET}  $1"; }
ok()   { echo -e "${GREEN}✔${RESET}  $1"; }
warn() { echo -e "${YELLOW}!${RESET}  $1"; }

########################################
# VERSION TRACKING
# ~/.local/share/blueak/.versions stores
# key=value pairs of installed versions.
# Bump a VERSION var below to trigger an
# update on the next login.
########################################

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

########################################
# SKEL COPY HELPER
# Copies a file from /etc/skel if the
# source exists and dest is missing or
# has changed (e.g. after image update).
########################################

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
    # Git workflow
    for pkg in lazygit git-delta gh gitleaks; do brew_ensure "$pkg"; done

    # Shell / terminal
    for pkg in atuin tmux tldr; do brew_ensure "$pkg"; done

    # Data & scripting
    for pkg in jq yq xh; do brew_ensure "$pkg"; done

    # Security / SOC
    for pkg in trivy grype; do brew_ensure "$pkg"; done

    # File management & productivity
    for pkg in yazi duf dust age; do brew_ensure "$pkg"; done

    # Fonts — homebrew/cask-fonts tap deprecated, fonts now in main tap
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
# TAG-BASED FILE BROWSER
########################################

log "--- Tag-Based File Browser ---"

xdg-mime default aktags.desktop inode/directory

########################################
# NYXT BROWSER
########################################

log "--- Nyxt Browser ---"

if ! flatpak list --user --app 2>/dev/null | grep -q "org.nyxt.Nyxt"; then
    log "Installing Nyxt via Flatpak..."
    flatpak install --user -y flathub org.nyxt.Nyxt 2>/dev/null \
        && ok "Nyxt installed" \
        || warn "Nyxt install failed (non-fatal)"
else
    ok "Nyxt (Flatpak) present"
fi

# Eldritch theme config (flatpak: ~/.var/app/<id>/config/)
NYXT_CONFIG_DIR="$HOME/.var/app/org.nyxt.Nyxt/config"
mkdir -p "$NYXT_CONFIG_DIR"
cat > "$NYXT_CONFIG_DIR/config.lisp" << 'EOF'
;; ~/.config/nyxt/config.lisp
;; Eldritch theme for Nyxt
;; Palette source: github.com/eldritch-theme/eldritch

(define-configuration browser
  ((theme (make-instance 'theme:theme
    :dark-p t
    :background-color    "#212337"  ;; Sunken Depths Grey (bg)
    :on-background-color "#ebfafa"  ;; Lighthouse White (fg)
    :primary-color       "#323449"  ;; Shallow Depths Grey (current line / surface)
    :on-primary-color    "#ebfafa"  ;; Lighthouse White
    :secondary-color     "#7081d0"  ;; The Old One Purple (comments / muted)
    :on-secondary-color  "#ebfafa"
    :accent-color        "#04d1f9"  ;; Watery Tomb Blue (cyan / primary accent)
    :on-accent-color     "#212337"
    ;; Additional semantic slots (Nyxt 3.x)
    :success-color       "#37f499"  ;; Eldritch Green
    :warning-color       "#e9f941"  ;; Eldritch Yellow
    :highlight-color     "#f265b5"  ;; Eldritch Magenta/Pink
    :codeblock-color     "#9071f4"  ;; Eldritch Purple/Blue
    :text-color          "#ebfafa"
    :contrast-text-color "#212337"))))
EOF
ok "Nyxt Eldritch theme configured"

# Theme GTK to match Eldritch palette
mkdir -p "$HOME/.config/gtk-3.0"
cat > "$HOME/.config/gtk-3.0/settings.ini" << 'EOF'
[Settings]
gtk-application-prefer-dark-theme=1
gtk-theme-name=Adwaita-dark
gtk-color-scheme=bg:#212337,fg:#ebfafa,selected_bg_color:#323449,selected_fg_color:#ebfafa,accent_color:#04d1f9
EOF

mkdir -p "$HOME/.config/gtk-4.0"
cat > "$HOME/.config/gtk-4.0/settings.ini" << 'EOF'
[Settings]
gtk-application-prefer-dark-theme=1
gtk-theme-name=Adwaita-dark
gtk-color-scheme=bg:#212337,fg:#ebfafa,selected_bg_color:#323449,selected_fg_color:#ebfafa,accent_color:#04d1f9
EOF
ok "GTK theme configured for Eldritch palette"

########################################
# SYSTEMD USER UNITS
########################################

log "--- Systemd user units ---"
mkdir -p ~/.config/systemd/user ~/.config/environment.d

# filetagger — AI file tagging daemon
skel_copy ".config/systemd/user/filetagger.service"
skel_copy ".config/environment.d/filetagger.conf"

systemctl --user daemon-reload 2>/dev/null || true

if ! systemctl --user is-enabled filetagger &>/dev/null 2>&1; then
    filetagger init 2>/dev/null || true
    systemctl --user enable --now filetagger 2>/dev/null \
        && ok "filetagger enabled and started" \
        || warn "filetagger failed — check: journalctl --user -u filetagger"
elif ! systemctl --user is-active --quiet filetagger 2>/dev/null; then
    systemctl --user start filetagger 2>/dev/null \
        && ok "filetagger started" \
        || warn "filetagger failed to start"
else
    ok "filetagger running"
fi

# cac-init — CAC smart card login-time setup
skel_copy ".config/systemd/user/cac-init.service"
skel_copy ".local/bin/cac-init.sh"
[[ -f "$HOME/.local/bin/cac-init.sh" ]] && chmod +x "$HOME/.local/bin/cac-init.sh"

systemctl --user daemon-reload 2>/dev/null || true

if ! systemctl --user is-enabled cac-init &>/dev/null 2>&1; then
    systemctl --user enable --now cac-init 2>/dev/null \
        && ok "cac-init enabled" \
        || warn "cac-init failed to enable — run: cac-setup.sh --doctor"
else
    ok "cac-init enabled"
fi

########################################
# 5. CAC SETUP
########################################

log "--- CAC setup ---"

# User NSS database — needed by Chrome, certutil, document signing
if [[ ! -f "$HOME/.pki/nssdb/cert9.db" ]]; then
    mkdir -p "$HOME/.pki/nssdb"
    certutil -d sql:"$HOME/.pki/nssdb" -N --empty-password 2>/dev/null \
        && ok "NSS database created" \
        || warn "certutil not available — NSS DB not created"
else
    ok "NSS database present"
fi

# GnuPG scdaemon — prevent it from stealing the reader from pcscd
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

) # end subshell — sourcing shell is unaffected regardless of what happened above

return 0 2>/dev/null || true