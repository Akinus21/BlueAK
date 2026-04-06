FROM ghcr.io/ublue-os/bluefin:latest

# 1. Add Terra repo and install terra-release
RUN dnf install -y --nogpgcheck \
    --repofrompath 'terra,https://repos.fyralabs.com/terra$releasever' \
    terra-release

# 2. Install stack
RUN dnf install -y \
    noctalia-shell \
    niri \
    ulauncher \
    alacritty \
    swaybg \
    matugen

# 3. Configs and cleanup
COPY config/niri/ /etc/skel/.config/niri/
COPY config/noctalia/ /etc/skel/.config/noctalia/
RUN dnf clean all && rm -rf /var/cache/dnf/*