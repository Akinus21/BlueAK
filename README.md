# BlueAK

A Universal Blue bootc image template that builds an OCI image and bootable disk images (ISO, qcow2, raw). Based on [Bluefin](https://projectbluefin.io/), it provides a refined keyboard-centric desktop experience with the [Niri](https://github.com/niri-wm/niri) compositor and [Noctalia Shell](https://noctalia.dev).

## What's Included

### In the Image (Containerfile)

**Desktop & Window Management**
- [Niri](https://github.com/niri-wm/niri) — scrollable workspace compositor
- [Ulauncher](https://ulauncher.io) — application launcher
- [Alacritty](https://alacritty.org) — GPU-accelerated terminal
- `swaybg` — wallpaper daemon
- `earlyoom` — early OOM killer

**Productivity**
- LibreOffice — office suite
- Okular — PDF viewer
- `android-tools` (adb)

**Shell & CLI**
- Zsh + [Oh-My-Zsh](https://ohmyz.sh) + [Powerlevel10k](https://github.com/romkatv/powerlevel10k)
- Zsh plugins: autosuggestions, syntax-highlighting, completions
- `fzf`, `eza`, `bat`, `zoxide`, `btop`, `fd-find`, `ripgrep`, `just`, `git`
- Python 3 + pip + virtualenv
- `tesseract` + langpack (OCR)
- `poppler-utils`, `odt2txt` (document conversion)

**Smart Card / CAC Support**
- `pcsc-lite`, `pcsc-lite-ccid`, `pcsc-tools`, `OpenSC`, `nss-tools`, `p11-kit`
- DoD PKI CA certificates installed to system trust store

**Noctalia Shell**
- `noctalia-shell` + `matugen` (from Terra/Fyra Labs repo)
- Purple Haze color scheme + wallpaper seeded to `/etc/skel/.config/noctalia/`
- Noctalia plugin repos: `Akinus21/noctalia-plugins` + `noctalia-dev/noctalia-plugins`

**LLM / AI**
- [Ollama](https://ollama.ai) — local LLM server (user systemd service)
- [OpenCode CLI](https://opencode.ai) — AI coding assistant

**Tools (planned)**
- [AKSpraypainter](https://github.com/Akinus21/akspraypainter) — syncs Noctalia theme colors to wallpaper (planned)

**Session & State**
- `nirinit` — session restore utility
- `blueak-init` — bootstrap script (systemd user service)
- `bootc-fetch-apply-updates` — staged updates, nightly reboot at 3 AM

**Theme (Eldritch)**
- GTK3/4 dark theme via Adwaita-dark + color overrides
- Eldritch color palette for terminal (P10k)

### After Boot (blueak-init)

Runs on every login via systemd user service. Installs / updates:

**CLI Packages (Homebrew + npm)**
| Package | Source |
|---------|--------|
| lazygit, git-delta, gh, gitleaks | Homebrew |
| atuin, tmux, tldr | Homebrew |
| jq, yq, xh | Homebrew |
| trivy, grype | Homebrew |
| yazi, duf, dust, age | Homebrew |
| aktags | Homebrew (Akinus21/tap) |
| iron | Homebrew |
| bitwarden-cli | Homebrew |
| blueak-session-manager | Homebrew (Akinus21/tap) |
| aktools | Homebrew (Akinus21/tap) |
| @bitwarden/cli | npm |

**Flatpak**
- Bitwarden Desktop (flathub)

**System Services**
- Ollama — started and enabled
- AkTags daemon — desktop autostart entry

**Noctalia Plugins** (git sparse-checkout from `Akinus21/noctalia-plugins`)
- `niri-keybinds` — Niri keybindings
- `linkding` — bookmark manager plugin
- `bitwarden` — Bitwarden integration plugin

**Config Sync** (from `/etc/skel` to `~`)
- Zsh config (`.zshrc`, `.p10k.zsh`)
- Justfile
- GTK settings (Eldritch dark)
- Surf config (`.surf/config.h`, `.surf/style.css`)
- Noctalia color scheme (Purple Haze)
- Noctalia wallpaper

**CAC Setup** — runs `/etc/skel/.local/bin/cac-setup`

## Building

### Prerequisites

- A machine running a bootc image (Bazzite, Bluefin, Aurora, or Fedora Atomic)
- GitHub account with Actions enabled

### Initial Setup

1. **Clone and configure:**
   ```bash
   git clone https://github.com/Akinus21/BlueAK.git
   cd BlueAK
   ```

2. **Generate a cosign key for image signing:**
   ```bash
   COSIGN_PASSWORD="" cosign generate-key-pair
   ```

3. **Add `SIGNING_SECRET` to GitHub Secrets** — paste the contents of `cosign.key`

4. **Edit `Justfile`** — change `image_name` to your preferred image name (e.g., `blueak`)

5. **Push to trigger CI:**
   ```bash
   git add Containerfile Justfile cosign.pub
   git commit -m "Initial setup"
   git push
   ```

### Local Build

On a bootc system with podman:
```bash
just build
```

### Building Disk Images

```bash
just build-qcow2   # QCOW2 VM image
just build-iso     # Bootable ISO
just build-raw     # Raw disk image
```

## First Login

On first login, `blueak-init` runs automatically via systemd user service.

To force re-run:
```bash
rm ~/.local/share/blueak/.sync-done && systemctl --user start blueak-init
```

## Repository Structure

```
config/
  blueak-init/       # First-login bootstrap script
  cac/               # Smart card setup script
  noctalia/          # Noctalia configs + color schemes + wallpaper
  niri/              # Compositor configuration
  systemd/user/      # User systemd services
  zsh/               # Zshrc + powerlevel10k
build_files/
  build.sh           # Package customizations (called from Containerfile)
Containerfile        # Image build entrypoint
Justfile             # Build task runner
```

## Community

- [Universal Blue Forums](https://universal-blue.discourse.group/)
- [Universal Blue Discord](https://discord.gg/WEu6BdFEtp)
- [bootc discussions](https://github.com/bootc-dev/bootc/discussions)
