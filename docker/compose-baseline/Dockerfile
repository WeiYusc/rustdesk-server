FROM debian:bookworm-slim

RUN apt-get update \
  && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    ca-certificates \
    iproute2 \
    procps \
  && rm -rf /var/lib/apt/lists/*

COPY target/release/hbbs /usr/local/bin/hbbs
COPY target/release/hbbr /usr/local/bin/hbbr
COPY target/release/rustdesk-utils /usr/local/bin/rustdesk-utils
COPY docker/compose-baseline/healthcheck.sh /usr/local/bin/rustdesk-healthcheck

RUN chmod +x \
    /usr/local/bin/hbbs \
    /usr/local/bin/hbbr \
    /usr/local/bin/rustdesk-utils \
    /usr/local/bin/rustdesk-healthcheck

WORKDIR /data
VOLUME ["/data"]
