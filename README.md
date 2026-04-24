# BlueAK

A Universal Blue bootc image template that builds an OCI image and bootable disk images (ISO, qcow2, raw). Based on [Bluefin]([https://github.com/ublue-os/bazzite](https://projectbluefin.io/), it provides a refined desktop experience with the [Noctalia shell](https://noctalia.dev), [Nyxt](https://nyxt.atlascode.dev) browser, and the "Eldritch" dark theme.

## What It Includes

- **Noctalia Shell** — desktop shell with live theme sync
- **Nyxt Browser** — flatpak with GTK/CAC filesystem overrides
- **CAC Smart Card Support** — pcscd, OpenSC, NSS db, Firefox, Okular PKCS#11
- **Ollama** — local LLM server (user systemd service)
- **AkTags** — tag-based file browser
- **Homebrew** — curated CLI packages (git-delta, gh, atuin, yazi, trivy, etc.)
- **Eldritch Theme** — unified dark color palette across GTK3/4, Nyxt, terminal, and Noctalia

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

## Theme System

BlueAK uses the **Eldritch** dark theme (Purple Haze variant) as its default. The theme is applied through:

- **Noctalia** — reads `~/.config/noctalia/colors.json` for the active theme; `~/.config/noctalia/colorschemes/` for the GUI picker
- **Noctalia-gtk** — syncs Noctalia colors to system GTK theme
- **Nyxt** — uses `set-nyxt-theme` script to match browser colors to the active Noctalia theme
- **GTK3/4** — `settings.ini` files in `config/gtk-3.0/` and `config/gtk-4.0/`
- **Terminal** — P10k zsh config with Eldritch colors

To change the Nyxt theme, run:
```bash
set-nyxt-theme <theme-name>   # eldritch, purple-haze, dracula, nord, noctalia
```

## First Login

On first login, `blueak-init` (triggered via systemd user service) runs:

1. Seeds Noctalia color schemes to `~/.config/noctalia/`
2. Installs Nyxt flatpak with CAC/filesystem overrides
3. Enables AkTags daemon, Ollama, noctalia-gtk
4. Installs Homebrew packages
5. Runs CAC smart card setup
6. Sets default Nyxt theme (synced to Noctalia)

To force re-run: `rm ~/.local/share/blueak/.first-run-done && systemctl --user start blueak-init`

## Repository Structure

```
config/
  blueak-init/       # First-login bootstrap script
  cac/               # Smart card setup script
  noctalia/          # Noctalia configs + color schemes
  niri/              # Compositor configuration
  nyxt/              # Browser config + themes
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
