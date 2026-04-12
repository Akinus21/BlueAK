FROM ghcr.io/ublue-os/bluefin:latest

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 0. Remove GNOME desktop environment
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
RUN dnf remove -y \
    gnome-shell \
    gnome-session \
    gnome-shell-extensions \
    gnome-control-center \
    gdm \
    mutter \
    && dnf autoremove -y || true

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
# 3. Install greetd + regreet (display manager for niri)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
RUN dnf install -y \
    greetd \
    greetd-selinux \
    regreet

# Configure greetd to launch regreet → niri
RUN mkdir -p /etc/greetd && \
    printf '[terminal]\nvt = 1\n\n[default_session]\ncommand = "regreet"\nuser = "greeter"\n' \
    > /etc/greetd/config.toml

# regreet config: launch niri as the session
RUN mkdir -p /etc/regreet && \
    printf '[commands]\nenvironments = [["niri-session"]]\n\n[background]\npath = ""\nfit = "Cover"\n' \
    > /etc/regreet/config.toml

RUN systemctl enable greetd && systemctl disable gdm 2>/dev/null || true

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 4. CAC smart card support
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
# 5. Install DoD PKI CA certificates
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
# 6. 1Password GUI + CLI
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
RUN rpm --import https://downloads.1password.com/linux/keys/1password.asc && \
    tee /etc/yum.repos.d/1password.repo <<'EOF'
[1password]
name=1Password Stable Channel
baseurl=https://downloads.1password.com/linux/rpm/stable/x86_64
enabled=1
gpgcheck=1
gpgkey=https://downloads.1password.com/linux/keys/1password.asc
EOF

RUN dnf install -y \
    1password \
    1password-cli

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 7. Zsh + shell tooling
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

# Set zsh as default shell for new users via /etc/default/useradd
RUN sed -i 's|^SHELL=.*|SHELL=/bin/zsh|' /etc/default/useradd 2>/dev/null || \
    echo 'SHELL=/bin/zsh' >> /etc/default/useradd

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 8. Oh-my-zsh + Powerlevel10k + configs → /etc/skel
#    New users get a fully wired shell on first login.
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# Install OMZ into skel so it's copied on useradd
RUN git clone --depth=1 https://github.com/ohmyzsh/ohmyzsh.git /etc/skel/.oh-my-zsh

# Install Powerlevel10k theme into OMZ custom themes
RUN git clone --depth=1 https://github.com/romkatv/powerlevel10k.git \
    /etc/skel/.oh-my-zsh/custom/themes/powerlevel10k

# Install zsh plugins into OMZ custom plugins
RUN git clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions.git \
    /etc/skel/.oh-my-zsh/custom/plugins/zsh-autosuggestions && \
    git clone --depth=1 https://github.com/zsh-users/zsh-syntax-highlighting.git \
    /etc/skel/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting && \
    git clone --depth=1 https://github.com/zsh-users/zsh-completions.git \
    /etc/skel/.oh-my-zsh/custom/plugins/zsh-completions

# Copy your p10k config into skel
COPY config/zsh/p10k.zsh /etc/skel/.p10k.zsh

# Write the skel .zshrc — cleaned up from your existing one:
#   - Duplicate PATH entries collapsed
#   - OP_SERVICE_ACCOUNT_TOKEN removed (sourced from ~/.config/aktools/secrets at runtime)
#   - p10k sourced from OMZ custom theme (not linuxbrew)
#   - All your plugins wired in
RUN cat > /etc/skel/.zshrc << 'ZSHRC'
# Enable Powerlevel10k instant prompt. Must stay near the top.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# PATH — single declaration, deduplicated
export PATH="$HOME/.opencode/bin:$HOME/.local/bin:$HOME/bin:/usr/local/bin:$PATH"

# Oh My Zsh
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="powerlevel10k/powerlevel10k"

plugins=(
  git
  zsh-autosuggestions
  zsh-syntax-highlighting
  zsh-completions
  fzf
)

source "$ZSH/oh-my-zsh.sh"

# zsh-completions
autoload -U compinit && compinit

# zoxide (smarter cd)
eval "$(zoxide init zsh)"

# fzf shell integration
if command -v fzf &>/dev/null; then
  source <(fzf --zsh) 2>/dev/null || true
fi

# eza aliases (modern ls)
alias ls='eza --icons'
alias ll='eza -lah --icons --git'
alias lt='eza --tree --icons'

# bat alias
alias cat='bat --style=auto'

# Editor
export EDITOR='nvim'
export VISUAL='nvim'

# 1Password CLI shell integration
if command -v op &>/dev/null; then
  eval "$(op completion zsh)"; compdef _op op
fi

# aktools secrets (OP_SERVICE_ACCOUNT_TOKEN lives here, not in .zshrc)
[[ -f "$HOME/.config/aktools/secrets" ]] && source "$HOME/.config/aktools/secrets"

# aktools aliases
[[ -f "$HOME/.aktools/aliases.sh" ]] && source "$HOME/.aktools/aliases.sh"

# Powerlevel10k config
[[ -f ~/.p10k.zsh ]] && source ~/.p10k.zsh
ZSHRC

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 9. just recipes (justfile in /etc/skel for new users)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
COPY config/just/justfile /etc/skel/justfile

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 10. bootc update: stage-only (no --apply), nightly reboot at 3 AM
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# Override bootc-fetch-apply-updates.service to stage only (no reboot)
RUN mkdir -p /etc/systemd/system/bootc-fetch-apply-updates.service.d && \
    printf '[Service]\nExecStart=\nExecStart=/usr/bin/bootc upgrade --quiet\n' \
    > /etc/systemd/system/bootc-fetch-apply-updates.service.d/stage-only.conf

# Restore the original timer schedule (staging can happen anytime)
# The upstream timer already uses OnBootSec + OnUnitInactiveSec so no override needed here.

# Nightly reboot service — only reboots if a staged update is pending
RUN cat > /etc/systemd/system/bootc-nightly-reboot.service << 'EOF'
[Unit]
Description=Nightly reboot if bootc update is staged
ConditionPathExists=/run/ostree-booted

[Service]
Type=oneshot
ExecStart=/bin/bash -c '\
  STATUS=$(bootc status --json 2>/dev/null); \
  STAGED=$(echo "$STATUS" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get(\"status\",{}).get(\"staged\") or \"\")" 2>/dev/null); \
  if [ -n "$STAGED" ] && [ "$STAGED" != "null" ]; then \
    echo "Staged update found ($STAGED), rebooting..."; \
    systemctl reboot; \
  else \
    echo "No staged update. Skipping reboot."; \
  fi'
EOF

RUN cat > /etc/systemd/system/bootc-nightly-reboot.timer << 'EOF'
[Unit]
Description=Nightly reboot check for staged bootc updates
ConditionPathExists=/run/ostree-booted

[Timer]
OnCalendar=*-*-* 03:00:00
RandomizedDelaySec=10m
Persistent=false

[Install]
WantedBy=timers.target
EOF

RUN systemctl enable bootc-nightly-reboot.timer

# rpm-ostreed-automatic already pinned to 3 AM via existing override — leave it.

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 11. Configs
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
COPY config/niri/     /etc/skel/.config/niri/
COPY config/noctalia/ /etc/skel/.config/noctalia/

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 12. Cleanup
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
RUN dnf clean all && rm -rf /var/cache/dnf/*
