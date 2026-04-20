# BlueAK

Universal Blue bootc image template. This repo builds OCI images and bootable disk images (ISO, qcow2, raw).

## Working in this Repo

- **Always push your changes when you have completed and tested them** before ending the session
- Use the SSH key: `GIT_SSH_COMMAND="ssh -i /config/.ssh/github -o StrictHostKeyChecking=no" git push`
- GitHub CLI: `/usr/bin/gh` (use `gh auth login` first on a new machine)

## Key Files

- `Containerfile` - image build entrypoint (like Dockerfile)
- `Justfile` - task runner with build/lint/format commands
- `build_files/build.sh` - packages and customizations called from Containerfile
- `config/` - desktop environment config (gdm, greetd, niri, systemd, zsh, etc.)

## Developer Commands

```bash
just build              # Build container image (podman build)
just build-qcow2        # Build qcow2 VM image (uses BIB)
just build-iso          # Build ISO image
just build-raw          # Build raw VM image
just rebuild-qcow2     # Build image then convert to qcow2
just lint               # shellcheck all .sh files
just format             # shfmt all .sh files
just check             # Verify just file syntax
just clean              # Remove build artifacts
```

## Build Artifact Locations

- Container image: local podman storage (tagged as `localhost/image-template:latest`)
- VM/disk images: `output/qcow2/`, `output/iso/`, `output/raw/`
- ISO config: `disk_config/iso.toml` (modify before building ISOs)

## Image Signing

- `cosign.key` must NOT be committed (in .gitignore)
- `cosign.pub` is the public key, safe to commit
- GitHub Actions uses `SIGNING_SECRET` secret for automated signing

## Building on Local Machine

1. Must run on a bootc system (Bazzite, Bluefin, Aurora, or Fedora Atomic)
2. Image must be tagged `localhost/<name>:<tag>` for VM builds
3. VM builds require rootful podman (handled by `_rootful_load_image` recipe)
4. BIB (Bootc Image Builder) runs in privileged container: `quay.io/centos-bootc/bootc-image-builder:latest`

## Architecture Notes

- `config/` subdirs (gdm, greetd, niri, systemd, zsh, etc.) are copied into the image at build time
- No tests in traditional sense - verify by building images
- This is a template; `image_name` in Justfile should be customized on fork

## Eldritch Theme (BlueAK Color Palette)

The "Eldritch" theme defines BlueAK's unified color system across multiple applications.

| Role        | Hex       | Name                      |
|-------------|-----------|---------------------------|
| Background  | `#212337` | Sunken Depths Grey        |
| Foreground  | `#ebfafa` | Lighthouse White          |
| Surface     | `#323449` | Shallow Depths Grey       |
| Accent      | `#04d1f9` | Watery Tomb Blue (cyan)   |
| Secondary   | `#7081d0` | The Old One Purple        |
| Success     | `#37f499` | Eldritch Green            |
| Warning     | `#e9f941` | Eldritch Yellow           |
| Highlight   | `#f265b5` | Eldritch Magenta/Pink     |
| Code        | `#9071f4` | Eldritch Purple/Blue      |

**Applications that use this palette:**
- **Nyxt** → `~/.config/nyxt/config.lisp` (Lisp theme config)
- **GTK3** → `~/.config/gtk-3.0/settings.ini`
- **GTK4** → `~/.config/gtk-4.0/settings.ini`
- **Terminal colors** → `config/zsh/` (P10k, zshrc)
- **GTK apps** → via Adwaita-dark + `gtk-color-scheme` overrides

**Source:** [eldritch-theme/eldritch](https://github.com/eldritch-theme/eldritch)

