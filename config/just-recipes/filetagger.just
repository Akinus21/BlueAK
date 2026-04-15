# ── FileTagger + TagSpaces recipes ──────────────────────────────────────────
# Add these to your existing ~/justfile

# Show filetagger daemon status
ft-status:
    filetagger status
    systemctl --user status filetagger --no-pager

# Tail filetagger daemon logs
ft-logs:
    journalctl --user -u filetagger -f

# Restart filetagger daemon
ft-restart:
    systemctl --user restart filetagger
    systemctl --user status filetagger --no-pager

# Open filetagger web UI in browser
ft-ui:
    xdg-open http://localhost:7432

# Update filetagger from git and restart
ft-update:
    cd ~/.local/share/filetagger/src && git pull
    ~/.local/share/filetagger/venv/bin/pip install -q -e ~/.local/share/filetagger/src
    systemctl --user restart filetagger
    echo "FileTagger updated and restarted."

# Force re-tag all files
ft-retag:
    filetagger retag-all

# Search files from CLI (usage: just ft-search "query")
ft-search query:
    filetagger search "{{query}}"

# Set Ollama URL (persists to environment.d)
ft-set-ollama url:
    sed -i "s|^FILETAGGER_OLLAMA_URL=.*|FILETAGGER_OLLAMA_URL={{url}}|" \
        ~/.config/environment.d/filetagger.conf
    systemctl --user daemon-reload
    systemctl --user restart filetagger
    echo "Ollama URL set to {{url}}"

# Update TagSpaces AppImage to latest
tagspaces-update:
    #!/usr/bin/env bash
    set -euo pipefail
    LATEST=$(curl -fsSL https://api.github.com/repos/tagspaces/tagspaces/releases/latest \
        | grep '"tag_name"' | sed 's/.*"v\([^"]*\)".*/\1/')
    echo "Latest TagSpaces: $LATEST"
    APPIMAGE="$HOME/.local/share/tagspaces/TagSpaces-${LATEST}.AppImage"
    if [[ -f "$APPIMAGE" ]]; then
        echo "Already up to date."
        exit 0
    fi
    curl -fsSL --retry 3 \
        "https://github.com/tagspaces/tagspaces/releases/download/v${LATEST}/tagspaces-linux-x86_64-${LATEST}.AppImage" \
        -o "$APPIMAGE"
    chmod +x "$APPIMAGE"
    # Update wrapper
    echo "#!/usr/bin/env bash" > "$HOME/.local/bin/tagspaces"
    echo "exec \"$APPIMAGE\" \"\$@\"" >> "$HOME/.local/bin/tagspaces"
    chmod +x "$HOME/.local/bin/tagspaces"
    # Update .desktop
    sed -i "s|Exec=.*AppImage|Exec=$APPIMAGE|" \
        "$HOME/.local/share/applications/tagspaces.desktop"
    update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
    # Clean up old versions
    find "$HOME/.local/share/tagspaces" -name "TagSpaces-*.AppImage" \
        ! -name "TagSpaces-${LATEST}.AppImage" -delete
    echo "TagSpaces updated to $LATEST"
