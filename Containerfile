# Start from the Bluefin bootc image
FROM ghcr.io/ublue-os/bluefin:latest

# 1. Use the DIRECT RAW link to the repo file (Fixes the "Missing Section Header" error)
RUN curl -fsSL https://githubusercontent.com -o /etc/yum.repos.d/terra.repo

# 2. Install Noctalia, Niri, and Ulauncher
# We include 'noctalia-qs' as it is the mandatory shell runner
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
