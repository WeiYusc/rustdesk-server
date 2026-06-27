FROM debian:bookworm-slim

ARG S6_OVERLAY_VERSION=3.2.0.0
ARG S6_ARCH=x86_64

ADD https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-noarch.tar.xz /tmp/s6-overlay-noarch.tar.xz
ADD https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-${S6_ARCH}.tar.xz /tmp/s6-overlay-${S6_ARCH}.tar.xz

RUN apt-get update \
  && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    procps \
    tzdata \
    xz-utils \
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
