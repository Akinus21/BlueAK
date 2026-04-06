FROM ghcr.io/ublue-os/bluefin:latest

# 1. Add Terra repo and install terra-release in one shot (official method)
RUN dnf install -y --nogpgcheck \
    --repofrompath 'terra,https://repos.fyralabs.com/terra$releasever' \
    terra-release

# 2. Install noctalia-shell (pulls in noctalia-qs automatically) + rest of stack
RUN dnf install -y \
    noctalia-shell \
    niri \
    ulauncher \
    alacritty \
    swaybg \
    matugen

# 3. Safety check
RUN which niri && which noctalia-shell

# 4. Configs and cleanup
COPY config/niri/ /etc/skel/.config/niri/
COPY config/noctalia/ /etc/skel/.config/noctalia/
RUN dnf clean all && rm -rf /var/cache/dnf/*