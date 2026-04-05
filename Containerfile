# Start from the Bluefin bootc image
FROM ghcr.io/ublue-os/bluefin:latest

# 1. FIX: Added 'raw.' to the URL and the full path to the repo file
RUN curl -fsSL https://githubusercontent.com -o /etc/yum.repos.d/terra.repo

# 2. Import the GPG key to avoid silent 'untrusted package' errors
RUN rpm --import https://fyralabs.com

# 3. Install your stack
RUN dnf install -y \
    terra-release \
    niri \
    noctalia-shell \
    noctalia-qs \
    ulauncher \
    alacritty \
    swaybg \
    matugen

# 4. Safety Check: If this fails, the GitHub Action will tell us immediately
RUN which niri && which noctalia-shell && which ulauncher

# 5. Configs and Cleanup
COPY config/niri/ /etc/skel/.config/niri/
COPY config/noctalia/ /etc/skel/.config/noctalia/
RUN dnf clean all && rm -rf /var/cache/dnf/*
