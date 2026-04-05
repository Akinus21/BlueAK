# Start from the Bluefin bootc image
FROM ghcr.io/ublue-os/bluefin:latest

# 1. Add the Terra repository using the official subatomic link
# This is more reliable for bootc builds than the standard DNF command
RUN curl -fsSL https://github.com -o /etc/yum.repos.d/terra.repo

# 2. Install Noctalia, its runtime, and Niri
# 'noctalia-qs' is the Quickshell fork required to run the shell
RUN dnf install -y \
    terra-release \
    niri \
    noctalia-shell \
    noctalia-qs \
    ulauncher \
    alacritty \
    swaybg \
    matugen

# 3. Verification: This ensures the build fails if the binary is missing
RUN which noctalia-shell && which qs

# 4. Copy configurations
COPY config/niri/ /etc/skel/.config/niri/
COPY config/noctalia/ /etc/skel/.config/noctalia/

# 5. Cleanup
RUN dnf clean all && rm -rf /var/cache/dnf/*
