FROM debian:bookworm-slim

ARG S6_OVERLAY_VERSION=3.2.0.0
ARG S6_ARCH=x86_64
ARG S6_OVERLAY_NOARCH_SHA256=4b0c0907e6762814c31850e0e6c6762c385571d4656eb8725852b0b1586713b6
ARG S6_OVERLAY_ARCH_SHA256=ad982a801bd72757c7b1b53539a146cf715e640b4d8f0a6a671a3d1b560fe1e2
ARG RUSTDESK_FULL_S6_SERVER_COMMIT=unknown
ARG RUSTDESK_FULL_S6_API_COMMIT=unknown
ARG RUSTDESK_FULL_S6_WEB_COMMIT=unknown
ARG RUSTDESK_FULL_S6_IMAGE=rustdesk-server-full-s6:local
ARG RUSTDESK_FULL_S6_BUILT_AT=unknown

LABEL org.opencontainers.image.title="rustdesk-server-full-s6" \
  org.opencontainers.image.description="Integrated RustDesk server, API, and Web Admin full-s6 image" \
  org.opencontainers.image.source="https://github.com/WeiYusc/rustdesk-server" \
  org.opencontainers.image.revision="${RUSTDESK_FULL_S6_SERVER_COMMIT}" \
  org.opencontainers.image.created="${RUSTDESK_FULL_S6_BUILT_AT}" \
  org.opencontainers.image.version="${RUSTDESK_FULL_S6_IMAGE}" \
  org.opencontainers.image.vendor="WeiYusc" \
  org.opencontainers.image.ref.name="${RUSTDESK_FULL_S6_IMAGE}" \
  org.opencontainers.image.rustdesk-api-revision="${RUSTDESK_FULL_S6_API_COMMIT}" \
  org.opencontainers.image.rustdesk-api-web-revision="${RUSTDESK_FULL_S6_WEB_COMMIT}"

RUN apt-get update \
  && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    procps \
    tzdata \
    xz-utils \
  && if [ "${S6_ARCH}" != "x86_64" ] && [ "${S6_OVERLAY_ARCH_SHA256}" = "ad982a801bd72757c7b1b53539a146cf715e640b4d8f0a6a671a3d1b560fe1e2" ]; then \
    echo "S6_OVERLAY_ARCH_SHA256 must be set for S6_ARCH=${S6_ARCH}" >&2; \
    exit 1; \
  fi \
  && curl -fsSL -o /tmp/s6-overlay-noarch.tar.xz "https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-noarch.tar.xz" \
  && curl -fsSL -o /tmp/s6-overlay-${S6_ARCH}.tar.xz "https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-${S6_ARCH}.tar.xz" \
  && echo "${S6_OVERLAY_NOARCH_SHA256}  /tmp/s6-overlay-noarch.tar.xz" | sha256sum -c - \
  && echo "${S6_OVERLAY_ARCH_SHA256}  /tmp/s6-overlay-${S6_ARCH}.tar.xz" | sha256sum -c - \
  && tar -C / -Jxpf /tmp/s6-overlay-noarch.tar.xz \
  && tar -C / -Jxpf /tmp/s6-overlay-${S6_ARCH}.tar.xz \
  && rm -rf /tmp/s6-overlay*.tar.xz /var/lib/apt/lists/* \
  && ln -s /run /var/run

COPY server-bin/hbbs /usr/bin/hbbs
COPY server-bin/hbbr /usr/bin/hbbr
COPY server-bin/rustdesk-utils /usr/bin/rustdesk-utils
COPY api-bin/apimain /app/apimain
COPY api-runtime/conf /app/conf
COPY api-runtime/resources /app/resources
COPY rootfs /
COPY healthcheck.sh /usr/bin/healthcheck.sh
COPY build-info.json /etc/rustdesk-full-s6-build.json

RUN chmod +x \
    /usr/bin/hbbs \
    /usr/bin/hbbr \
    /usr/bin/rustdesk-utils \
    /app/apimain \
    /usr/bin/healthcheck.sh \
    /etc/s6-overlay/s6-rc.d/hbbs/run \
    /etc/s6-overlay/s6-rc.d/hbbr/run \
    /etc/s6-overlay/s6-rc.d/api/run \
    /etc/s6-overlay/s6-rc.d/key-secret/up.real \
  && mkdir -p /data /app/data /app/runtime

ENV RELAY=127.0.0.1:21117
ENV ENCRYPTED_ONLY=0
ENV RUSTDESK_API_GIN_API_ADDR=0.0.0.0:21114
ENV RUSTDESK_API_GIN_RESOURCES_PATH=resources
ENV RUSTDESK_API_RUSTDESK_ID_SERVER=127.0.0.1:21116
ENV RUSTDESK_API_RUSTDESK_RELAY_SERVER=127.0.0.1:21117
ENV RUSTDESK_API_RUSTDESK_API_SERVER=http://127.0.0.1:21114
ENV RUSTDESK_API_RUSTDESK_KEY_FILE=/data/id_ed25519.pub

WORKDIR /data
VOLUME ["/data", "/app/data"]

EXPOSE 21114 21115 21116 21116/udp 21117 21118 21119

HEALTHCHECK --interval=10s --timeout=5s CMD /usr/bin/healthcheck.sh

ENTRYPOINT ["/init"]
