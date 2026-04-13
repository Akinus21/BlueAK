FROM ghcr.io/ublue-os/bluefin:latest

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 1. Add Terra repo and install terra-release
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
RUN dnf install -y --nogpgcheck \
    --repofrompath 'terra,https://repos.fyralabs.com/terra$releasever' \
    terra-release

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 2. Install desktop stack + display manager (all Terra packages in one shot)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
RUN dnf install -y \
    noctalia-shell \
    niri \
    ulauncher \
    alacritty \
    swaybg \
    matugen \
    greetd \
    greetd-selinux \
    gtkgreet \
    cage

# Configure greetd to use dynamic HiDPI-aware greeter script
# Script lives in /usr/local/bin so SELinux allows execution by the greeter user
RUN mkdir -p /etc/greetd && \
    printf '[terminal]\nvt = 1\n\n[default_session]\ncommand = "/usr/local/bin/blueak-greeter"\nuser = "greeter"\n' \
    > /etc/greetd/config.toml

# Copy Eldritch-themed gtkgreet stylesheet
COPY config/greetd/gtkgreet.css      /etc/greetd/gtkgreet.css

# Install greeter launch script to /usr/local/bin (SELinux bin_t context — executable)
COPY config/greetd/start-greeter.sh  /usr/local/bin/blueak-greeter
RUN chmod +x /usr/local/bin/blueak-greeter

# Declare greeter system user via sysusers.d — works correctly in bootc/ostree images
# (useradd writes to /etc/passwd which does not persist reliably in container builds)
RUN printf 'u greeter - "Greeter user" /var/lib/greeter /sbin/nologin\n' \
    > /usr/lib/sysusers.d/greeter.conf

# Disable GDM, enable greetd — GNOME packages stay installed (required by Bluefin base)
RUN systemctl disable gdm 2>/dev/null || true
RUN systemctl enable greetd

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
# NOTE: 1Password GUI is installed as a Flatpak post-boot:
#   flatpak install flathub com.onepassword.1Password

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 6. Zsh + shell tooling
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
    just

# Set zsh as default shell for new users
RUN sed -i 's|^SHELL=.*|SHELL=/bin/zsh|' /etc/default/useradd 2>/dev/null || \
    echo 'SHELL=/bin/zsh' >> /etc/default/useradd

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 7. Oh-my-zsh + Powerlevel10k + plugins → /etc/skel
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
# 10. Configs + first-login bootstrap
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
COPY config/niri/     /etc/skel/.config/niri/
COPY config/noctalia/ /etc/skel/.config/noctalia/
COPY config/profile.d/blueak-init.sh /etc/profile.d/blueak-init.sh
RUN chmod +x /etc/profile.d/blueak-init.sh

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 11. Cleanup
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
RUN dnf clean all && rm -rf /var/cache/dnf/*
