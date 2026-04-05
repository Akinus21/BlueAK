# Start from the Bluefin bootc image
FROM ghcr.io/ublue-os/bluefin:latest

# 1. Manually add the Terra repo (Required for Noctalia & Ulauncher on Fedora Atomic)
RUN curl -Lo /etc/yum.repos.d/terra.repo https://fyralabs.com

# 2. Install everything in one layer to keep the image clean
# Added ulauncher and kept noctalia-shell, niri, and utilities
RUN dnf install -y \
    terra-release \
    niri \
    noctalia-shell \
    ulauncher \
    alacritty \
    swaybg \
    matugen

# 3. Copy your local configurations into the image
# This ensures your Niri binds and Noctalia settings are pre-baked
COPY config/niri/ /etc/skel/.config/niri/
COPY config/noctalia/ /etc/skel/.config/noctalia/

# 4. Cleanup dnf metadata to minimize image size
RUN dnf clean all && \
    rm -rf /var/cache/dnf/*
