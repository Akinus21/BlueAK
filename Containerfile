# Start from the Bluefin bootc image
FROM ghcr.io/ublue-os/bluefin:latest

# 1. Add Terra repo
RUN curl -fsSL https://raw.githubusercontent.com/terrafirmacraft/terra/main/terra.repo \
    -o /etc/yum.repos.d/terra.repo

# 2. Import the Terra/Fyra GPG key
RUN rpm --import https://fyralabs.com/gpg.key

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

# 4. Safety Check
RUN which niri && which noctalia-shell && which ulauncher

# 5. Configs and Cleanup
COPY config/niri/ /etc/skel/.config/niri/
COPY config/noctalia/ /etc/skel/.config/noctalia/
RUN dnf clean all && rm -rf /var/cache/dnf/*