FROM ghcr.io/ublue-os/bluefin:latest

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 1. Add Terra repo and install terra-release
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
RUN dnf install -y --nogpgcheck \
    --repofrompath 'terra,https://repos.fyralabs.com/terra$releasever' \
    terra-release

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 2. Install desktop stack
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
RUN dnf install -y \
    noctalia-shell \
    niri \
    ulauncher \
    alacritty \
    swaybg \
    matugen

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 3. CAC smart card support
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
RUN dnf install -y \
    pcsc-lite \
    pcsc-lite-ccid \
    pcsc-tools \
    opensc \
    nss-tools \
    p11-kit \
    p11-kit-server \
    gnutls-utils \
    openssl \
    unzip

RUN mkdir -p /etc/pkcs11/modules && \
    printf 'module: /usr/lib64/pkcs11/opensc-pkcs11.so\ncritical: no\n' \
    > /etc/pkcs11/modules/opensc.module

RUN if [ -f /etc/opensc/opensc.conf ]; then \
        grep -q "force_card_driver" /etc/opensc/opensc.conf || \
        sed -i '/^app default {/a\\tcard_drivers = cac;\n\tforce_card_driver = cac;' \
            /etc/opensc/opensc.conf; \
    fi

RUN systemctl enable pcscd.socket

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
# 5. 1Password CLI
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
RUN rpm --import https://downloads.1password.com/linux/keys/1password.asc && \
    printf '[1password]\nname=1Password Stable Channel\nbaseurl=https://downloads.1password.com/linux/rpm/stable/x86_64\nenabled=1\ngpgcheck=1\ngpgkey=https://downloads.1password.com/linux/keys/1password.asc\n' \
    > /etc/yum.repos.d/1password.repo

RUN dnf install -y 1password-cli
# NOTE: 1Password GUI installed as Flatpak post-boot:
#   flatpak install flathub com.onepassword.1Password

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 6. Zsh + shell tooling + Python + OCR deps
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
RUN dnf install -y \
    zsh \
    zsh-autosuggestions \
    zsh-syntax-highlighting \
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
    odt2txt

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
# 10. AkTags + Noctalia-gtk — build both from source in one Rust layer
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

RUN mkdir -p /etc/skel/files

# Install Rust toolchain + all build deps (shared by Aktags and Noctalia-gtk)
# iced (Aktags GUI) needs wayland/X11/EGL/font devel headers
RUN dnf install -y \
    rust cargo gcc \
    gtk4-devel libadwaita-devel \
    wayland-devel libxkbcommon-devel \
    mesa-libEGL-devel \
    libX11-devel libXcursor-devel libXi-devel libXrandr-devel \
    fontconfig-devel freetype-devel \
    openssl-devel

# ── AkTags — tag-based AI file browser (source build, no releases) ───────────
RUN curl -fsSL https://github.com/Akinus21/Aktags/archive/refs/heads/main.tar.gz \
        -o /tmp/aktags.tar.gz && \
    tar xzf /tmp/aktags.tar.gz -C /tmp && \
    cd /tmp/Aktags-main && \
    cargo build --release && \
    install -m755 target/release/aktags /usr/bin/aktags && \
    printf '[Desktop Entry]\nName=AkTags\nComment=Tag-based AI file browser\nExec=aktags\nIcon=folder\nType=Application\nCategories=Utility;FileManager;\nMimeType=inode/directory;\n' \
        > /usr/share/applications/aktags.desktop && \
    update-desktop-database /usr/share/applications/ 2>/dev/null || true && \
    rm -rf /tmp/Aktags-main /tmp/aktags.tar.gz

# ── Noctalia-gtk — GTK theme color sync daemon (source build) ────────────────
RUN curl -fsSL https://github.com/Akinus21/Noctalia-gtk/archive/refs/heads/main.tar.gz \
        -o /tmp/noctalia-gtk.tar.gz && \
    tar xzf /tmp/noctalia-gtk.tar.gz -C /tmp && \
    cd /tmp/Noctalia-gtk-main && \
    cargo build --release && \
    install -m755 target/release/noctalia-gtk /usr/local/bin/noctalia-gtk && \
    rm -rf /tmp/Noctalia-gtk-main /tmp/noctalia-gtk.tar.gz

# Remove build toolchain — keeps final image lean
RUN dnf remove -y \
    rust cargo gcc \
    gtk4-devel libadwaita-devel \
    wayland-devel libxkbcommon-devel \
    mesa-libEGL-devel \
    libX11-devel libXcursor-devel libXi-devel libXrandr-devel \
    fontconfig-devel freetype-devel \
    openssl-devel && \
    dnf clean all

# ── Systemd user services (seeded into /etc/skel so every new user gets them) ─
RUN mkdir -p /etc/skel/.config/systemd/user
COPY config/systemd/aktags-daemon.service    /etc/skel/.config/systemd/user/aktags-daemon.service
COPY config/systemd/noctalia-gtk.service     /etc/skel/.config/systemd/user/noctalia-gtk.service

# ── Noctalia color config seed ────────────────────────────────────────────────
RUN mkdir -p /etc/skel/.config/noctalia
COPY config/noctalia/ /etc/skel/.config/noctalia/

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 11. Configs + first-login bootstrap
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
COPY config/niri/     /etc/skel/.config/niri/
COPY config/profile.d/blueak-init.sh /etc/profile.d/blueak-init.sh
RUN chmod +x /etc/profile.d/blueak-init.sh

# ── Eldritch Theme — GTK ────────────────────────────────────────────────────
RUN mkdir -p /etc/skel/.config/gtk-3.0 /etc/skel/.config/gtk-4.0
COPY config/gtk-3.0/settings.ini /etc/skel/.config/gtk-3.0/settings.ini
COPY config/gtk-4.0/settings.ini /etc/skel/.config/gtk-4.0/settings.ini

# ── Eldritch Theme — Nyxt ───────────────────────────────────────────────────
RUN mkdir -p /etc/skel/.var/app/org.nyxt.Nyxt/config
COPY config/nyxt/config.lisp /etc/skel/.var/app/org.nyxt.Nyxt/config/config.lisp

# ── Flatpak ────────────────────────────────────────────────────────────────
RUN flatpak remote-add --user --if-not-exists flathub \
    https://dl.flathub.org/repo/flathub.flatpakrepo || true
RUN flatpak install --user -y flathub org.nyxt.Nyxt || true

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 12. Cleanup
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
RUN dnf clean all && rm -rf /var/cache/dnf/*
