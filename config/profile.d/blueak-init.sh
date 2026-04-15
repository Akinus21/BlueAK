#!/usr/bin/env bash
# /etc/profile.d/blueak-init.sh
# Runs once per user on first login. Idempotent — safe to re-run.

INIT_STAMP="$HOME/.local/share/blueak/.init-done"

if [[ -f "$INIT_STAMP" ]]; then
    exit 0
fi

# ── Flatpak remotes ──────────────────────────────────────────────────────────
flatpak remote-add --user --if-not-exists flathub \
    https://dl.flathub.org/repo/flathub.flatpakrepo

# ── Flatpak GUI apps ─────────────────────────────────────────────────────────
flatpak install --user -y flathub com.onepassword.1Password

# ── TagSpaces AppImage ───────────────────────────────────────────────────────
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

    # Wrapper so 'tagspaces' works from any terminal
    printf '#!/usr/bin/env bash\nexec "%s" "$@"\n' "$TAGSPACES_APPIMAGE" \
        > "$TAGSPACES_BIN"
    chmod +x "$TAGSPACES_BIN"

    # .desktop entry for ulauncher / app grid
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

    # Extract icon from AppImage
    cd /tmp && "$TAGSPACES_APPIMAGE" --appimage-extract \
        'usr/share/icons' >/dev/null 2>&1 || true
    ICON_SRC=$(find /tmp/squashfs-root/usr/share/icons -name "*.png" \
        2>/dev/null | sort | tail -1)
    [[ -n "$ICON_SRC" ]] && cp "$ICON_SRC" "$TAGSPACES_DIR/tagspaces.png"
    rm -rf /tmp/squashfs-root

    update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
    echo "[blueak-init] TagSpaces installed."
fi

# ── FileTagger — venv is pre-built in the image at /usr/share/filetagger/venv
# Just initialize the user config and enable the systemd user service.
# ─────────────────────────────────────────────────────────────────────────────
if ! systemctl --user is-enabled filetagger &>/dev/null; then
    echo "[blueak-init] Enabling FileTagger daemon..."

    # Initialize user config (~/.filetagger/config.json)
    # FILETAGGER_OLLAMA_URL is already set via ~/.config/environment.d/filetagger.conf
    filetagger init

    # Enable and start the systemd user service
    systemctl --user daemon-reload
    systemctl --user enable --now filetagger

    echo "[blueak-init] FileTagger daemon started."
fi

# ── Mark init complete ────────────────────────────────────────────────────────
mkdir -p "$(dirname "$INIT_STAMP")"
touch "$INIT_STAMP"

echo "[blueak-init] First-login setup complete."
