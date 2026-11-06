FROM docker.io/library/node:24.22.0-bookworm

ARG ORCA_VERSION=1.4.229
LABEL org.opencontainers.image.source="https://github.com/juftin/home-ops"

# Orca's Electron headless server needs Xvfb and the desktop runtime libraries.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        dbus-x11 libasound2 libatk-bridge2.0-0 libatspi2.0-0 libdrm2 libgbm1 \
        libgtk-3-0 libnotify4 libnss3 libsecret-1-0 libxcomposite1 libxdamage1 \
        libxfixes3 libxkbcommon0 libxrandr2 libxss1 libxtst6 tini xauth xdg-utils xvfb \
    && rm -rf /var/lib/apt/lists/*

RUN case "$(dpkg --print-architecture)" in \
        amd64) checksum=ed336a8788965b598790821370f50e0b8d02f2ca89add38666df05e80e6328e4 ;; \
        arm64) checksum=5a5bc963a985f5a992fa7c7d84f2d2a124a33a83f7dd7638ab167f7aae549b34 ;; \
        *) exit 1 ;; \
    esac \
    && curl --fail --silent --show-error --location --retry 3 \
        "https://github.com/stablyai/orca/releases/download/v${ORCA_VERSION}/orca-ide_${ORCA_VERSION}_$(dpkg --print-architecture).deb" \
        -o /tmp/orca.deb \
    && printf '%s  /tmp/orca.deb\n' "${checksum}" | sha256sum --check \
    && dpkg-deb --extract /tmp/orca.deb / \
    && rm /tmp/orca.deb \
    && ln -s /opt/Orca/resources/bin/orca-ide /usr/local/bin/orca \
    && mkdir -p /home/orca /workspace \
    && chown node:node /home/orca /workspace

ENV HOME=/home/orca \
    ORCA_USER_DATA_PATH=/home/orca/.config/Orca \
    PATH=/home/orca/.local/bin:$PATH \
    ORCA_SERVE_RUNTIME=electron \
    ORCA_ELECTRON_NO_SANDBOX=1 \
    LIBGL_ALWAYS_SOFTWARE=1

COPY --chmod=0755 start.sh /usr/local/bin/start-orca
USER 1000:1000
WORKDIR /workspace
EXPOSE 6768
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/start-orca"]
CMD ["serve", "--port", "6768", "--pairing-address", "127.0.0.1"]
