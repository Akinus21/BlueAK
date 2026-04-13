#!/usr/bin/env bash
# /usr/libexec/blueak-apply-gdm-theme
# Unpacks gnome-shell-theme.gresource, injects Eldritch CSS, repacks.
# Run once at image build time via RUN in Containerfile.
set -euo pipefail

GRESOURCE="/usr/share/gnome-shell/gnome-shell-theme.gresource"
WORKDIR=$(mktemp -d /tmp/gdm-theme-XXXXX)
THEME_CSS="/usr/share/blueak/gdm-eldritch.css"

cleanup() { rm -rf "$WORKDIR"; }
trap cleanup EXIT

echo "[blueak] Extracting gnome-shell gresource..."
cd "$WORKDIR"

# Extract all resources
while IFS= read -r resource; do
    rel="${resource#/org/gnome/shell/}"
    dir=$(dirname "$rel")
    mkdir -p "$dir"
    gresource extract "$GRESOURCE" "$resource" > "$rel"
done < <(gresource list "$GRESOURCE")

# Inject Eldritch theme at end of gnome-shell.css
echo "[blueak] Injecting Eldritch theme..."
cat "$THEME_CSS" >> theme/gnome-shell.css

# Generate gresource XML manifest
MANIFEST="$WORKDIR/gnome-shell-theme.gresource.xml"
echo '<?xml version="1.0" encoding="UTF-8"?>' > "$MANIFEST"
echo '<gresources>' >> "$MANIFEST"
echo '  <gresource prefix="/org/gnome/shell/theme">' >> "$MANIFEST"
while IFS= read -r f; do
    echo "    <file>${f#theme/}</file>" >> "$MANIFEST"
done < <(find theme -type f | sort)
echo '  </gresource>' >> "$MANIFEST"
echo '</gresources>' >> "$MANIFEST"

# Repack
echo "[blueak] Repacking gresource..."
cd "$WORKDIR/theme"
glib-compile-resources \
    --sourcedir="$WORKDIR/theme" \
    --target="$GRESOURCE" \
    "$MANIFEST"

echo "[blueak] GDM Eldritch theme applied."
