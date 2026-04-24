# Changelog

All notable changes to BlueAK are documented here.

## [Unreleased]

## [0.2.0] — 2026-04-24

### Fixed
- **blueak-init not running on login** — removed stale `profile.d/blueak-init.sh` that was shadowing the systemd service; now uses only `blueak-init.service` (systemd user service)
- **Nyxt flatpak not installing** — blueak-init now installs Nyxt flatpak on first login with proper CAC/filesystem overrides, instead of relying on build-time install that didn't persist
- **nyxt.desktop wrong Exec path** — changed from `/usr/bin/nyxt` to `flatpak run org.nyxt.Nyxt`

### Changed
- **Purple Haze as default Noctalia theme** — `colors.json` now seeds with Purple Haze flat colors; `colorschemes/purple-haze/` added with nested dark/light format for GUI picker
- **noctalia-gtk** — now downloaded from GitHub releases (`Akinus21/Noctalia-gtk`) instead of built from source
- **Nyxt** — replaced GitHub AppImage with flatpak (`org.nyxt.Nyxt`) with filesystem overrides for GTK theme and CAC access

### Added
- **blueak-init Noctalia color scheme seeding** — creates `~/.config/noctalia/colorschemes/` directory structure for proper GUI theme discovery

## [0.1.0] — 2026-04-22

### Added
- **Noctalia Shell** via Terra repo (`noctalia-shell` + `qs` binary), spawned via niri `spawn-at-startup`
- **Ollama** local LLM server with systemd user service (`graphical-session.target`)
- **AkTags** tag-based file browser via Homebrew (`brew install aktags`)
- **Bitwarden CLI** via Homebrew (`brew install bitwarden-cli`)
- **CAC smart card setup** — zero-interaction `cac-setup` script configuring pcscd, OpenSC, NSS db, Firefox, Okular PKCS#11
- **Okular** PDF viewer with CAC PKCS#11 signing support
- **Eldritch Theme** — unified dark color palette across GTK3/4, Nyxt, terminal, Noctalia
- **CI disk cleanup** — prevents runner out-of-space failures during build