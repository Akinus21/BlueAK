ARG BASE_IMAGE=ghcr.io/ublue-os/bluefin:latest
FROM ${BASE_IMAGE}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 1. Terra repo is added dynamically at runtime (see blueak-init.sh) since
#    the Terra repo for Fedora 43 can have transient availability issues.
#    noctalia-shell and matugen are installed at runtime with fallback to
#    ensure the build is resilient.
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 2. Install desktop stack
# NOTE: noctalia-shell and matugen come from Terra repo (Fyra Labs) which can
# have transient mirror issues. They are also installed at runtime via
# blueak-init.sh if not present, making the build more resilient.
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
RUN dnf install -y \
    niri \
    alacritty \
    swaybg \
    earlyoom \
    libreoffice \
    okular \
    android-tools

# Noctalia Shell — via Terra repo (Fyra Labs)
# https://docs.noctalia.dev/getting-started/installation
RUN dnf install -y --skip-broken --nogpgcheck --repofrompath 'terra,https://repos.fyralabs.com/terra$releasever' terra-release && \
    dnf install -y --skip-broken noctalia-shell || echo "Terra repo unavailable — install noctalia-shell at runtime"

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 3. CAC smart card support
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# opensc provides the PKCS#11 module for DoD CAC/PIV cards
# udev rules for CAC reader hotplug detection
RUN dnf install -y --skip-broken \
    pcsc-lite \
    pcsc-lite-ccid \
    pcsc-tools \
    opensc \
    nss-tools \
    p11-kit \
    p11-kit-server \
    gnutls-utils \
    openssl \
    unzip && \
    mkdir -p /etc/pkcs11/modules && \
    printf 'module: /usr/lib64/pkcs11/opensc-pkcs11.so\ncritical: no\n' \
        > /etc/pkcs11/modules/opensc.module

# Create OpenSC config forcing CAC driver for DoD CAC cards
RUN mkdir -p /etc/opensc && \
    printf 'app default {\n    card_drivers = cac;\n    force_card_driver = cac;\n}\n' \
    > /etc/opensc/opensc.conf.new && \
    if [ -f /etc/opensc/opensc.conf ]; then \
        grep -q "force_card_driver" /etc/opensc/opensc.conf || \
        cat /etc/opensc/opensc.conf >> /etc/opensc/opensc.conf.new; \
    fi && \
    mv /etc/opensc/opensc.conf.new /etc/opensc/opensc.conf

# Install udev rules for common CAC readers (Gemalto, SCR, OMNIKEY, etc.)
RUN mkdir -p /etc/udev/rules.d && \
    printf '# CAC/PCSC smart card readers\n' \
    'SUBSYSTEM=="usb", ATTR{idVendor}=="04e6", ATTR{idProduct}=="e003", MODE="0660", GROUP="pcscd"\n' \
    'SUBSYSTEM=="usb", ATTR{idVendor}=="04e6", ATTR{idProduct}=="e004", MODE="0660", GROUP="pcscd"\n' \
    'SUBSYSTEM=="usb", ATTR{idVendor}=="04e6", ATTR{idProduct}*="*scr*", MODE="0660", GROUP="pcscd"\n' \
    'SUBSYSTEM=="usb", ATTR{idVendor}=="0dc3", MODE="0660", GROUP="pcscd"\n' \
    'SUBSYSTEM=="usb", ATTR{idVendor}=="0b97", ATTR{idProduct}=="7762", MODE="0660", GROUP="pcscd"\n' \
    'SUBSYSTEM=="usb", ATTR{idVendor}=="0b97", ATTR{idProduct}=="7761", MODE="0660", GROUP="pcscd"\n' \
    'SUBSYSTEM=="usb", ATTR{idVendor}=="1a34", MODE="0660", GROUP="pcscd"\n' \
    'SUBSYSTEM=="usb", ATTR{idVendor}=="0a5c", MODE="0660", GROUP="pcscd"\n' \
    'KERNEL=="pcsc*", SUBSYSTEM=="usbmisc", MODE="0660", GROUP="pcscd"\n' \
    > /etc/udev/rules.d/92-cac-reader.rules && \
    printf 'SUBSYSTEM=="usb", ENV{ID_SMARTCARD}=="1", MODE="0660", GROUP="pcscd"\n' \
    >> /etc/udev/rules.d/92-cac-reader.rules

# Enable pcscd socket so it's active on boot (hotplug-aware)
RUN systemctl enable pcscd.service && \
    systemctl enable pcscd.socket 2>/dev/null || true

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 4. Install DoD PKI CA certificates
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
RUN DOD_CERT_URL="https://dl.dod.cyber.mil/wp-content/uploads/pki-pke/zip/unclass-certificates_pkcs7_DoD.zip" && \
    mkdir -p /tmp/dod_certs && \
    curl -fsSL --retry 3 -o /tmp/dod_certs/dod.zip "$DOD_CERT_URL" && \
    unzip -q /tmp/dod_certs/dod.zip -d /tmp/dod_certs/extracted/ && \
    CERT_DIR="$(find /tmp/dod_certs/extracted -name '*.p7b' -printf '%h\n' | sort -u | head -1)" && \
    mkdir -p /etc/pki/ca-trust/source/anchors && \
    for p7b in "$CERT_DIR"/*.p7b; do \
        base="$(basename "${p7b%.p7b}")"; \
        dest="/etc/pki/ca-trust/source/anchors/dod-${base}.pem"; \
        openssl pkcs7 -inform PEM -print_certs -in "$p7b" > "$dest" 2>/dev/null || \
        openssl pkcs7 -inform DER -print_certs -in "$p7b" > "$dest" 2>/dev/null || \
        rm -f "$dest"; \
    done && \
    update-ca-trust extract && \
    rm -rf /tmp/dod_certs

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 6. Zsh + shell tooling + Python + OCR deps
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
RUN dnf install -y \
    zsh \
    fzf \
    eza \
    bat \
    zoxide \
    btop \
    fd-find \
    ripgrep \
    just \
    git \
    python3 \
    python3-pip \
    python3-virtualenv \
    tesseract \
    tesseract-langpack-eng \
    poppler-utils \
    odt2txt \
    npm

# ── OpenCode CLI ───────────────────────────────────────────────────────────────
# /usr/local is a file in the base image — clean it up before use
# HOME=/tmp needed since /root is also a file in the base image
RUN rm -rf /usr/local && mkdir -p /usr/local/bin && \
    HOME=/tmp npm config --global set prefix /usr/local && \
    HOME=/tmp npm install -g opencode-ai

RUN sed -i 's|^SHELL=.*|SHELL=/bin/zsh|' /etc/default/useradd 2>/dev/null || \
    echo 'SHELL=/bin/zsh' >> /etc/default/useradd

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 7. Oh-my-zsh + Powerlevel10k + plugins -> /etc/skel
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
RUN git clone --depth=1 https://github.com/ohmyzsh/ohmyzsh.git /etc/skel/.oh-my-zsh

RUN git clone --depth=1 https://github.com/romkatv/powerlevel10k.git \
    /etc/skel/.oh-my-zsh/custom/themes/powerlevel10k

RUN git clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions.git \
        /etc/skel/.oh-my-zsh/custom/plugins/zsh-autosuggestions && \
    git clone --depth=1 https://github.com/zsh-users/zsh-syntax-highlighting.git \
        /etc/skel/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting && \
    git clone --depth=1 https://github.com/zsh-users/zsh-completions.git \
        /etc/skel/.oh-my-zsh/custom/plugins/zsh-completions

COPY config/zsh/p10k.zsh /etc/skel/.p10k.zsh
COPY config/zsh/zshrc    /etc/skel/.zshrc

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 8. just recipes
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
COPY config/just/justfile /etc/skel/justfile

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 9. bootc update: stage-only, nightly reboot at 3 AM
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
RUN mkdir -p /etc/systemd/system/bootc-fetch-apply-updates.service.d && \
    printf '[Service]\nExecStart=\nExecStart=/usr/bin/bootc upgrade --quiet\n' \
    > /etc/systemd/system/bootc-fetch-apply-updates.service.d/stage-only.conf

COPY config/systemd/bootc-nightly-reboot.service /etc/systemd/system/bootc-nightly-reboot.service
COPY config/systemd/bootc-nightly-reboot.timer   /etc/systemd/system/bootc-nightly-reboot.timer

RUN systemctl enable bootc-nightly-reboot.timer

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 10. Systemd user services + Noctalia color config
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# ── AkTags — via Homebrew (Akinus21/homebrew-tap) ───────────────────────────
# Binary installed via brew install on login
COPY config/systemd/aktags-daemon.service /etc/skel/.config/systemd/user/aktags-daemon.service
COPY config/aktags/aktags.desktop /etc/skel/.config/autostart/aktags.desktop

# ── AKSpraypainter — theme-to-wallpaper color sync (planned) ────────────────
# TODO: Add AKSpraypainter binary once available
# Build: ensure this comment triggers CI

# ── Build cage from source (Wayland kiosk compositor for regreet) ───────────────
# cage-kiosk/cage v0.1.4 — compatible with Fedora 42's wlroots 0.19
# v0.3.0 requires wlroots 0.20 which is not available in Fedora 42
# Fedora puts wlroots.pc in /usr/lib64/pkgconfig — add to PKG_CONFIG_PATH
RUN dnf install -y --skip-broken \
    meson ninja-build scdoc \
    wayland-protocols-devel wayland-devel \
    pixman-devel libxkbcommon-devel wlroots-devel \
    libinput-devel && \
    mkdir -p /tmp/cage-src && \
    curl -fsSL https://github.com/cage-kiosk/cage/releases/download/v0.1.4/cage-0.1.4.tar.gz \
        -o /tmp/cage.tar.gz && \
    tar xzf /tmp/cage.tar.gz -C /tmp/cage-src --strip-components=1 && \
    PKG_CONFIG_PATH=/usr/lib64/pkgconfig:/usr/lib/pkgconfig:/usr/share/pkgconfig \
        meson setup /tmp/cage-src /tmp/cage-build --prefix=/usr -Dman-pages=disabled && \
        meson compile -C /tmp/cage-build && \
        meson install -C /tmp/cage-build && \
        rm -rf /tmp/cage-src /tmp/cage-build

# wtype — needed by cage/regreet for virtual keyboard input
RUN dnf install -y --skip-broken wtype || true

# ── Build regreet from source (clean GTK greeter for greetd) ──────────────────
# rharish101/ReGreet v0.3.0 — requires Rust 1.85+ (Fedora 42 has 1.95)
# Set CARGO_HOME to /tmp to avoid root home permission issues
# Use codegen-units=1 for faster builds in container memory constraints
RUN dnf install -y --skip-broken \
    rust cargo gtk4-devel libadwaita-devel \
    openssl-devel at-spi2-core-devel && \
    mkdir -p /tmp/regreet-src /tmp/cargo-home && \
    curl -fsSL https://github.com/rharish101/ReGreet/archive/refs/tags/0.3.0.tar.gz \
        -o /tmp/regreet.tar.gz && \
    tar xzf /tmp/regreet.tar.gz -C /tmp/regreet-src --strip-components=1 && \
    CARGO_HOME=/tmp/cargo-home HOME=/tmp cargo build --release \
        -j 4 \
        --manifest-path /tmp/regreet-src/Cargo.toml && \
    install -Dm755 /tmp/regreet-src/target/release/regreet /usr/local/bin/regreet && \
    rm -rf /tmp/regreet-src /tmp/cargo-home

# ── Noctalia color config seed + greeter templates ──────────────────────────────
RUN mkdir -p /etc/skel/.config/noctalia /etc/skel/.cache/noctalia
COPY config/noctalia/ /etc/skel/.config/noctalia/

# ── greetd + regreet + cage setup ──────────────────────────────────────────────
# greetd runs regreet inside cage (the Wayland compositor) for a GTK greeter
RUN dnf install -y --skip-broken greetd || true && \
    mkdir -p /etc/greetd

# Seed default greeter CSS (regreet uses /etc/greetd/regreet.css)
RUN printf '/* BlueAK default greeter CSS */\n' \
    'window { background: #0b070d; }\n' \
    'box.login-box, box#main-box { background: rgba(11,7,13,0.72); border-radius: 16px; }\n' \
    'label { color: #ad9bbb; }\n' \
    'entry { background: rgba(36,19,48,0.6); color: #ad9bbb; border-radius: 8px; }\n' \
    'button.suggested-action, button#login-button { background: #A8E000; color: #0C0E00; border-radius: 8px; }\n' \
    > /etc/greetd/regreet.css

# regreet-launch.sh: cage runs regreet with niri as the session
COPY config/greetd/regreet-launch.sh /etc/greetd/regreet-launch.sh
RUN chmod +x /etc/greetd/regreet-launch.sh

# greetd config using regreet inside cage
RUN printf '[terminal]\nvt = 1\n\n[default_session]\ncommand = "/etc/greetd/regreet-launch.sh"\nuser = "greeter"\n' > /etc/greetd/config.toml

# Greeter user setup
RUN id greeter &>/dev/null || useradd -r -m -s /usr/bin/nologin -c "Greeter" greeter && \
    usermod -aG video greeter && \
    usermod -aG input greeter

# Disable GDM; enable greetd as the display manager
RUN systemctl disable gdm 2>/dev/null || true
RUN systemctl enable greetd 2>/dev/null || true

# ── nirinit — session restore for niri ───────────────────────────────────────
# Download pre-built binary
RUN curl -fsSL \
    https://github.com/amaanq/nirinit/releases/download/v0.2.2/nirinit-x86_64-linux.tar.gz \
    -o /tmp/nirinit.tar.gz && \
    mkdir -p /tmp/nirinit-extract && \
    tar xzf /tmp/nirinit.tar.gz -C /tmp/nirinit-extract && \
    NIRINIT_PATH=$(find /tmp/nirinit-extract -type f -name nirinit 2>/dev/null | head -1) && \
    if [[ -n "$NIRINIT_PATH" ]]; then \
        mv "$NIRINIT_PATH" /usr/local/bin/nirinit && \
        chmod +x /usr/local/bin/nirinit; \
    fi && \
    rm -rf /tmp/nirinit*

# Note: niri-session-manager removed (cargo build fails due to /root/.cargo lock
# in container environment). Use nirinit for session restore instead.

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 11. Configs + first-login bootstrap (blueak-init)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# ── blueak-init script — copy first, then install ───────────────────────────────
COPY config/blueak-init/blueak-init /tmp/blueak-init
RUN mkdir -p /usr/local/bin && \
    install -m 755 /tmp/blueak-init /usr/local/bin/blueak-init && \
    rm -f /tmp/blueak-init

# ── System-wide zsh trigger: run blueak-init on every zsh login ───────────
# Existing users won't have the systemd user service from skel. This ensures
# blueak-init fires for ALL users on every shell login without skel dependency.
RUN echo '[[ -x /usr/local/bin/blueak-init ]] && /usr/local/bin/blueak-init' >> /etc/zshenv

# Also seed into /etc/skel/.zshrc for new users (belt-and-suspenders)
RUN echo '[[ -x /usr/local/bin/blueak-init ]] && /usr/local/bin/blueak-init' >> /etc/skel/.zshrc

# Seed blueak-init systemd user service for new users (desktop autostart removed to prevent double-trigger)
RUN mkdir -p /etc/skel/.config/systemd/user /etc/skel/.local/bin
COPY config/systemd/blueak-init.service /etc/skel/.config/systemd/user/blueak-init.service
COPY config/systemd/ollama.service /etc/skel/.config/systemd/user/ollama.service
COPY config/cac/cac-setup /etc/skel/.local/bin/cac-setup
RUN chmod +x /etc/skel/.local/bin/cac-setup

# Legacy profile.d script removed — replaced by systemd user service

ARG GAMING=false
RUN if [ "$GAMING" = "true" ]; then \
        echo "GAMING=true — installing gaming packages..."; \
        dnf install -y --skip-broken \
            gamemode gamescope mangohud goverlay \
            vulkan-tools vulkan-loader mesa-vulkan-drivers \
            mesa-dri-drivers libva libva-utils mesa-va-drivers \
            steam-devices || true; \
        dnf install -y --skip-broken wine winetricks || true; \
        dnf install -y --skip-broken lutris || true; \
        printf '# Gaming tweaks\nvm.max_map_count=2147483642\nkernel.split_lock_mitigate=0\n' > /etc/sysctl.d/99-gaming.conf; \
        groupadd -f gamemode; \
        touch /etc/blueak-gaming; \
        printf '#!/bin/sh\nexport __NV_PRIME_RENDER_OFFLOAD=1\nexport __GLX_VENDOR_LIBRARY_NAME=nvidia\nexport VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/nvidia_icd.x86_64.json:/usr/share/vulkan/icd.d/nvidia_icd.i686.json\n' > /etc/profile.d/blueak-nvidia-gaming.sh; \
    fi

COPY config/niri/     /etc/skel/.config/niri/

# ── Eldritch Theme — GTK ────────────────────────────────────────────────────
RUN mkdir -p /etc/skel/.config/gtk-3.0 /etc/skel/.config/gtk-4.0
COPY config/gtk-3.0/settings.ini /etc/skel/.config/gtk-3.0/settings.ini
COPY config/gtk-4.0/settings.ini /etc/skel/.config/gtk-4.0/settings.ini

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 12. Cleanup
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
RUN dnf clean all && rm -rf /var/cache/dnf/*
