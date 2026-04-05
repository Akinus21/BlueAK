# Start from the Bluefin bootc image
FROM ghcr.io/ublue-os/bluefin:latest

# 1. Use the FULL RAW URL for the Terra repo file
RUN curl -fsSL https://githubusercontent.com -o /etc/yum.repos.d/terra.repo

# 2. Import the GPG key manually to prevent DNF from failing silently
RUN rpm --import https://fyralabs.com

# 3. Install Noctalia, Niri, and Ulauncher in one step
# 'noctalia-qs' is the specific runtime needed for the shell
RUN dnf install -y \
    terra-release \
    niri \
    noctalia-shell \
    noctalia-qs \
    ulauncher \
    alacritty \
    swaybg \
    matugen

# 4. VERIFICATION: If these aren't found, the GitHub Action will FAIL (this is good!)
RUN which niri && which noctalia-shell && which ulauncher

# 5. Copy your local configurations
COPY config/niri/ /etc/skel/.config/niri/
COPY config/noctalia/ /etc/skel/.config/noctalia/

# 6. Cleanup
RUN dnf clean all && rm -rf /var/cache/dnf/*
