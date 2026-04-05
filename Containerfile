# Start from the Bluefin bootc image
FROM ghcr.io/ublue-os/bluefin:latest

# Enable COPR repositories for Niri and Noctalia
RUN dnf -y copr enable yalter/niri && \
    dnf -y copr enable zhangyi6324/noctalia-shell

# Install Niri, Noctalia, and essential Wayland utilities
RUN dnf -y install \
    niri \
    noctalia-shell \
    alacritty \
    fuzzel \
    swaybg

# Clean up dnf metadata to keep the image small
RUN dnf clean all && \
    rm -rf /var/cache/dnf/*
