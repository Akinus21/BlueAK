#!/usr/bin/env bash
# /etc/profile.d/blueak-init.sh
# Runs on every login. No-ops silently once everything is set up.
# Sets up the 'cli' distrobox and installs 1Password inside it.

# Only run for interactive login shells of real users (uid >= 1000)
[[ $- != *i* ]] && return
[[ "$(id -u)" -lt 1000 ]] && return

# ── Helpers ──────────────────────────────────────────────────────────────────

_log()  { echo "[blueak-init] $*"; }
_ok()   { echo "[blueak-init] ✔ $*"; }
_warn() { echo "[blueak-init] ! $*"; }

# ── Detect parent OS image for distrobox ─────────────────────────────────────

_get_image() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        case "$ID" in
            fedora)  echo "registry.fedoraproject.org/fedora:${VERSION_ID:-40}" ;;
            debian)  echo "docker.io/library/debian:stable" ;;
            ubuntu)  echo "docker.io/library/ubuntu:latest" ;;
            arch)    echo "docker.io/library/archlinux:latest" ;;
            *)       echo "registry.fedoraproject.org/fedora:40" ;;
        esac
    else
        echo "registry.fedoraproject.org/fedora:40"
    fi
}

# ── 1: Ensure 'cli' distrobox exists ─────────────────────────────────────────

if command -v distrobox &>/dev/null; then
    if ! distrobox list 2>/dev/null | grep -q "^cli "; then
        _log "Creating 'cli' distrobox..."
        IMAGE="$(_get_image)"
        _log "Using image: $IMAGE"
        distrobox create --name cli --image "$IMAGE" --yes
        _ok "'cli' distrobox created."
    else
        _ok "'cli' distrobox already exists."
    fi
else
    _warn "distrobox not found — skipping distrobox setup."
fi

# ── 2: Ensure 1Password CLI is installed in 'cli' ────────────────────────────

if command -v distrobox &>/dev/null && distrobox list 2>/dev/null | grep -q "^cli "; then

    OP_INSTALLED=$(distrobox enter cli -- bash -c 'command -v op &>/dev/null && echo yes || echo no' 2>/dev/null)

    if [[ "$OP_INSTALLED" != "yes" ]]; then
        _log "Installing 1Password CLI in 'cli' distrobox..."

        distrobox enter cli -- bash -c '
            set -e

            # Detect package manager
            if command -v dnf &>/dev/null; then
                sudo rpm --import https://downloads.1password.com/linux/keys/1password.asc
                sudo tee /etc/yum.repos.d/1password.repo > /dev/null <<EOF
[1password]
name=1Password Stable Channel
baseurl=https://downloads.1password.com/linux/rpm/stable/x86_64
enabled=1
gpgcheck=1
gpgkey=https://downloads.1password.com/linux/keys/1password.asc
EOF
                sudo dnf install -y 1password-cli

            elif command -v apt-get &>/dev/null; then
                curl -sS https://downloads.1password.com/linux/keys/1password.asc | \
                    sudo gpg --dearmor --output /usr/share/keyrings/1password-archive-keyring.gpg
                echo "deb [arch=amd64 signed-by=/usr/share/keyrings/1password-archive-keyring.gpg] \
https://downloads.1password.com/linux/debian/amd64 stable main" | \
                    sudo tee /etc/apt/sources.list.d/1password.list
                sudo apt-get update -qq && sudo apt-get install -y 1password-cli

            elif command -v pacman &>/dev/null; then
                sudo pacman -S --noconfirm 1password-cli

            else
                echo "ERROR: No supported package manager found in cli distrobox." >&2
                exit 1
            fi
        '

        # Export 'op' to ~/.local/bin so it's available on the host
        distrobox enter cli -- distrobox-export --bin /usr/bin/op --export-path "$HOME/.local/bin"
        _ok "1Password CLI installed and exported to ~/.local/bin."

    else
        _ok "1Password CLI already installed in 'cli'."

        # Re-export in case ~/.local/bin/op is missing (e.g. after home wipe)
        if [[ ! -f "$HOME/.local/bin/op" ]]; then
            distrobox enter cli -- distrobox-export --bin /usr/bin/op --export-path "$HOME/.local/bin"
            _ok "Re-exported 'op' to ~/.local/bin."
        fi
    fi
fi
