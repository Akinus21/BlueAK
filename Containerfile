FROM ghcr.io/ublue-os/bluefin:latest

# ── 1. Add Terra repo and install terra-release ───────────────────────────────
RUN dnf install -y --nogpgcheck \
    --repofrompath 'terra,https://repos.fyralabs.com/terra$releasever' \
    terra-release

# ── 2. Install desktop stack ──────────────────────────────────────────────────
RUN dnf install -y \
    noctalia-shell \
    niri \
    ulauncher \
    alacritty \
    swaybg \
    matugen

# ── 3. CAC smart card support ─────────────────────────────────────────────────
# Installs all middleware at the OS image layer so pcscd, pcsc_scan, and
# opensc-pkcs11.so are native to the host — no distrobox version mismatch.
# This fixes the pcsc-lite protocol mismatch (4:4 vs 4:5) seen when using
# the Fedora 40 distrobox pcsc_scan against the host Bluefin pcscd.
RUN dnf install -y \
    # PC/SC daemon + CCID driver for USB card readers (SCM SCR3500, etc.)
    pcsc-lite \
    pcsc-lite-ccid \
    pcsc-tools \
    # OpenSC: CAC/PIV smart card drivers + opensc-pkcs11.so PKCS#11 module
    opensc \
    # NSS tools: certutil + modutil for NSS database management
    nss-tools \
    # p11-kit: system PKCS#11 broker (Bluefin/Fedora preferred registration method)
    p11-kit \
    p11-kit-server \
    # GnuTLS utils: p11tool for cert inspection and debugging
    gnutls-utils \
    # Support tools
    openssl \
    unzip

# ── 4. Register OpenSC with p11-kit system-wide ───────────────────────────────
# Drops a module config so p11-kit proxies opensc-pkcs11.so to all NSS apps
# (Chrome, certutil, Firefox) without needing modutil per-user.
RUN mkdir -p /etc/pkcs11/modules && \
    printf 'module: /usr/lib64/pkcs11/opensc-pkcs11.so\ncritical: no\n' \
    > /etc/pkcs11/modules/opensc.module

# ── 5. Force OpenSC to use CAC driver (not PIV fallback) ─────────────────────
# Without this, OpenSC may detect CAC cards as PIV and signing certs won't
# be accessible. Injects into the app default {} block in opensc.conf.
RUN if [ -f /etc/opensc/opensc.conf ]; then \
        grep -q "force_card_driver" /etc/opensc/opensc.conf || \
        sed -i '/^app default {/a\\tcard_drivers = cac;\n\tforce_card_driver = cac;' \
            /etc/opensc/opensc.conf; \
    fi

# ── 6. Enable pcscd socket activation at image level ─────────────────────────
# Ensures pcscd starts on-demand when a card reader is accessed.
RUN systemctl enable pcscd.socket

# ── 7. Install DoD PKI CA certificates into the system trust store ────────────
# Fetches the current DISA bundle and adds all DoD root/intermediate CAs
# so CAC-authenticated sites are trusted natively without per-user setup.
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

# ── 8. Configs and cleanup ────────────────────────────────────────────────────
COPY config/niri/     /etc/skel/.config/niri/
COPY config/noctalia/ /etc/skel/.config/noctalia/

RUN dnf clean all && rm -rf /var/cache/dnf/*