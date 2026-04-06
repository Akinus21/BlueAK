FROM ghcr.io/ublue-os/bluefin:latest

# 1. Add Terra repo (correct URL for atomic Fedora)
RUN curl -fsSL https://github.com/terrapkg/subatomic-repos/raw/main/terra.repo \
    -o /etc/yum.repos.d/terra.repo

# 2. Install terra-release first so DNF trusts the repo, then the rest
RUN dnf install -y --nogpgcheck terra-release && \
    dnf install -y \
        niri \
        noctalia-shell \
        noctalia-qs \
        ulauncher \
        alacritty \
        swaybg \
        matugen

# 3. Safety Check
RUN which niri && which noctalia-shell && which ulauncher

# 4. Configs and Cleanup
COPY config/niri/ /etc/skel/.config/niri/
COPY config/noctalia/ /etc/skel/.config/noctalia/
RUN dnf clean all && rm -rf /var/cache/dnf/*