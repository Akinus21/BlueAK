FROM ghcr.io/ublue-os/bluefin:latest

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
    ulauncher \
    alacritty \
    swaybg \
    earlyoom \
    libreoffice \
    ollama && \
    dnf install -y --setopt=install_weak_deps=False \
    noctalia-shell \
    matugen \
    || echo "Terra repo packages not available at build time — will be installed at runtime"

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
    odt2txt \
    npm

# ── OpenCode CLI ───────────────────────────────────────────────────────────────
# /usr/local is a file in the base image — clean it up before use
# HOME=/tmp needed since /root is also a file in the base image
RUN rm -rf /usr/local && mkdir -p /usr/local/bin && \
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

# ── Noctalia-gtk binary — GTK theme color sync daemon ──────────────────────
# v0.00.1 release has x86_64 binary; installed at runtime by blueak-init if missing
COPY config/systemd/noctalia-gtk.service /etc/skel/.config/systemd/user/noctalia-gtk.service

# ── AkTags — via Homebrew (Akinus21/homebrew-tap) ───────────────────────────
# Binary installed via brew install on login
COPY config/systemd/aktags-daemon.service /etc/skel/.config/systemd/user/aktags-daemon.service
COPY config/aktags/aktags.desktop /etc/skel/.config/autostart/aktags.desktop

# ── Noctalia color config seed ────────────────────────────────────────────────
RUN mkdir -p /etc/skel/.config/noctalia
COPY config/noctalia/ /etc/skel/.config/noctalia/

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
RUN rm -rf /usr/local && mkdir -p /usr/local/bin && \
    install -m 755 /tmp/blueak-init /usr/local/bin/blueak-init && \
    rm -f /tmp/blueak-init

# Seed blueak-init systemd user service for new users (desktop autostart removed to prevent double-trigger)
RUN mkdir -p /etc/skel/.config/systemd/user /etc/skel/.local/bin
COPY config/systemd/blueak-init.service /etc/skel/.config/systemd/user/blueak-init.service
COPY config/systemd/ollama.service /etc/skel/.config/systemd/user/ollama.service
COPY config/cac/cac-setup /etc/skel/.local/bin/cac-setup
RUN chmod +x /etc/skel/.local/bin/cac-setup

# Legacy profile.d script removed — replaced by systemd user service
COPY config/niri/     /etc/skel/.config/niri/

# ── Eldritch Theme — GTK ────────────────────────────────────────────────────
RUN mkdir -p /etc/skel/.config/gtk-3.0 /etc/skel/.config/gtk-4.0
COPY config/gtk-3.0/settings.ini /etc/skel/.config/gtk-3.0/settings.ini
COPY config/gtk-4.0/settings.ini /etc/skel/.config/gtk-4.0/settings.ini

# ── Eldritch Theme — Nyxt ───────────────────────────────────────────────────
RUN mkdir -p /etc/skel/.config/nyxt/themes
COPY config/nyxt/config.lisp /etc/skel/.config/nyxt/config.lisp
COPY config/nyxt/themes/       /etc/skel/.config/nyxt/themes/
COPY config/nyxt/set-nyxt-theme /etc/skel/.local/bin/set-nyxt-theme
RUN chmod +x /etc/skel/.local/bin/set-nyxt-theme

# ── Nyxt — GitHub release tarball ──────────────────────────────────────────────
RUN NYXT_VERSION=$(curl -fsSL https://api.github.com/repos/atlas-engineer/nyxt/releases/latest \
      | grep '"tag_name"' | sed 's/.*"tag_name": *"\([^"]*\)".*/\1/') && \
    curl -fsSL \
      "https://github.com/atlas-engineer/nyxt/releases/download/${NYXT_VERSION}/Linux-Nyxt-x86_64.tar.gz" \
      -o /tmp/nyxt.tar.gz && \
    tar xzf /tmp/nyxt.tar.gz -C /tmp && \
    install -m 755 -D /tmp/Nyxt-x86_64.AppImage /usr/bin/nyxt && \
    rm -f /tmp/nyxt.tar.gz

# ── Nyxt — .desktop entry + MIME types ──────────────────────────────────────
COPY config/nyxt/nyxt.desktop /usr/share/applications/nyxt.desktop
RUN update-desktop-database /usr/share/applications/ 2>/dev/null || true

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 12. Cleanup
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
RUN dnf clean all && rm -rf /var/cache/dnf/*
