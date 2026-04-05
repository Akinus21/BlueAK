# Start from the Bluefin bootc image
FROM ghcr.io/ublue-os/bluefin:latest

# 1. Use the GitHub-hosted repo file to avoid host resolution issues
# This is the recommended method for Fedora Atomic/bootc images
RUN curl -fsSL https://github.com/terrapkg/subatomic-repos/raw/main/terra.repo -o /etc/yum.repos.d/terra.repo

# 2. Install everything in one layer
# terra-release ensures the repo stays updated if URLs change again
RUN dnf install -y \
    terra-release \
    niri \
    noctalia-shell \
    ulauncher \
    alacritty \
    swaybg \
    matugen

# 3. Copy your local configurations
COPY config/niri/ /etc/skel/.config/niri/
COPY config/noctalia/ /etc/skel/.config/noctalia/

# 4. Cleanup
RUN dnf clean all && \
    rm -rf /var/cache/dnf/*
