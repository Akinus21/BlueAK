#!/usr/bin/env bash
# /etc/profile.d/blueak-init.sh
# Sourced by /etc/zsh/zshenv for every shell — MUST NOT exit or crash.

INIT_STAMP="$HOME/.local/share/blueak/.init-done"

# Already initialized — return cleanly (not exit, this file is sourced)
if [[ -f "$INIT_STAMP" ]]; then
    return 0 2>/dev/null || true
fi

# Run all init in a subshell — crashes here cannot affect the parent shell
(
    set -e
    LOG="$HOME/.local/share/blueak/init.log"
    mkdir -p "$(dirname "$LOG")"
    exec > >(tee -a "$LOG") 2>&1

    echo "[blueak-init] Starting first-login setup..."

    # ── Flatpak remotes ──────────────────────────────────────────────────────
    flatpak remote-add --user --if-not-exists flathub \
        https://dl.flathub.org/repo/flathub.flatpakrepo || true

    # ── Flatpak GUI apps ─────────────────────────────────────────────────────
    flatpak install --user -y flathub com.1password.1Password || true

    # ── TagSpaces AppImage ───────────────────────────────────────────────────
    TAGSPACES_VERSION="6.10.5"
    TAGSPACES_DIR="$HOME/.local/share/tagspaces"
    TAGSPACES_BIN="$HOME/.local/bin/tagspaces"
    TAGSPACES_APPIMAGE="$TAGSPACES_DIR/TagSpaces-${TAGSPACES_VERSION}.AppImage"

    mkdir -p "$TAGSPACES_DIR" "$HOME/.local/bin"

    if [[ ! -f "$TAGSPACES_APPIMAGE" ]]; then
        echo "[blueak-init] Installing TagSpaces ${TAGSPACES_VERSION}..."
        curl -fsSL --retry 3 \
            "https://github.com/tagspaces/tagspaces/releases/download/v${TAGSPACES_VERSION}/tagspaces-linux-x86_64-${TAGSPACES_VERSION}.AppImage" \
            -o "$TAGSPACES_APPIMAGE"
        chmod +x "$TAGSPACES_APPIMAGE"

        printf '#!/usr/bin/env bash\nexec "%s" "$@"\n' "$TAGSPACES_APPIMAGE" \
            > "$TAGSPACES_BIN"
        chmod +x "$TAGSPACES_BIN"

        mkdir -p "$HOME/.local/share/applications"
        cat > "$HOME/.local/share/applications/tagspaces.desktop" << DESKTOP
[Desktop Entry]
Name=TagSpaces
Comment=Offline file manager with AI tagging support
Exec=$TAGSPACES_APPIMAGE %F
Icon=$TAGSPACES_DIR/tagspaces.png
Terminal=false
Type=Application
Categories=Utility;FileManager;
MimeType=inode/directory;
StartupWMClass=tagspaces
DESKTOP

        cd /tmp && "$TAGSPACES_APPIMAGE" --appimage-extract \
            'usr/share/icons' >/dev/null 2>&1 || true
        ICON_SRC=$(find /tmp/squashfs-root/usr/share/icons -name "*.png" \
            2>/dev/null | sort | tail -1)
        [[ -n "$ICON_SRC" ]] && cp "$ICON_SRC" "$TAGSPACES_DIR/tagspaces.png"
        rm -rf /tmp/squashfs-root

        update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
        echo "[blueak-init] TagSpaces installed."
    fi

    # ── FileTagger ───────────────────────────────────────────────────────────
    mkdir -p ~/.config/systemd/user ~/.config/environment.d

    cp /etc/skel/.config/systemd/user/filetagger.service \
       ~/.config/systemd/user/filetagger.service 2>/dev/null || true

    cp /etc/skel/.config/environment.d/filetagger.conf \
       ~/.config/environment.d/filetagger.conf 2>/dev/null || true

    if ! systemctl --user is-enabled filetagger &>/dev/null; then
        echo "[blueak-init] Enabling FileTagger daemon..."
        filetagger init || true
        systemctl --user daemon-reload
        systemctl --user enable --now filetagger || true
        echo "[blueak-init] FileTagger daemon started."
    fi

    echo "[blueak-init] First-login setup complete."

) && {
    mkdir -p "$(dirname "$INIT_STAMP")"
    touch "$INIT_STAMP"
} || {
    echo "[blueak-init] Setup had errors. Check ~/.local/share/blueak/init.log" >&2
    # Still stamp it so broken init doesn't re-run on every shell open
    mkdir -p "$(dirname "$INIT_STAMP")"
    touch "$INIT_STAMP"
}

return 0 2>/dev/null || true
