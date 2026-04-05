# Start from the Bluefin bootc image
FROM ghcr.io/ublue-os/bluefin:latest

# 1. Install the Terra repository for Noctalia and Quickshell
RUN dnf install -y --nogpgcheck \
    --repofrompath 'terra,https://repos.fyralabs.com/terra$releasever' \
    terra-release

# 2. Install Niri (from official Fedora repos) and Noctalia-shell
# Including essential utilities for a complete experience
RUN dnf install -y \
    niri \
    noctalia-shell \
    alacritty \
    fuzzel \
    swaybg \
    matugen

# 3. Optional: Copy your local configurations into the image
# This ensures Niri and Noctalia are configured on first boot
COPY config/niri/ /etc/skel/.config/niri/
COPY config/noctalia/ /etc/skel/.config/noctalia/

# 4. Cleanup to minimize image size
RUN dnf clean all && \
    rm -rf /var/cache/dnf/*
