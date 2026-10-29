# Capture image: VHS (ttyd, ffmpeg, headless chromium) + the released netclaw CLI.
#
# Why this shape: the release image (ubuntu:24.04, glibc) ships the CLI as a
# self-contained .NET single-file binary, and the VHS image (debian trixie, glibc 2.41,
# ICU and libsodium already present) runs it unmodified. So we take the VHS image and
# copy the CLI and its self-dropping launcher out of the release image. The CLI in a
# tape is therefore byte-for-byte the released one, never a host build.
#
# The container shares the daemon's network namespace and ~/.netclaw volume (see
# docker-compose.screenshots.yml), so `netclaw status` typed in a recording reaches the
# daemon over loopback the way a real user's CLI does.
ARG NETCLAW_IMAGE
ARG VHS_IMAGE=ghcr.io/charmbracelet/vhs:v0.12.1

FROM ${NETCLAW_IMAGE} AS netclaw

FROM ${VHS_IMAGE}

RUN apt-get update \
 && apt-get install -y --no-install-recommends gosu curl ca-certificates git jq \
 && rm -rf /var/lib/apt/lists/*

# Same uid/gid as the daemon so the shared ~/.netclaw volume is readable and writable.
RUN groupadd --gid 1654 netclaw \
 && useradd --uid 1654 --gid netclaw --create-home netclaw \
 && mkdir -p /home/netclaw/.netclaw /work/screenshots/output \
 && chown -R netclaw:netclaw /home/netclaw /work

# The skillserver CLI, used by the seed scripts to publish demo skills to the stack's skill server.
ARG SKILLSERVER_VERSION=0.4.1
RUN arch="$(uname -m)"; case "$arch" in x86_64) rid=x64 ;; aarch64) rid=arm64 ;; esac \
 && curl -fsSL "https://github.com/netclaw-dev/skill-server/releases/download/${SKILLSERVER_VERSION}/skillserver-${SKILLSERVER_VERSION}-linux-${rid}.tar.gz" \
  | tar -xz -C /usr/local/bin \
 && chmod +x /usr/local/bin/skillserver

COPY --from=netclaw /opt/netclaw/cli/netclaw /opt/netclaw/cli/netclaw
COPY --from=netclaw /usr/local/bin/netclaw /usr/local/bin/netclaw

COPY entrypoint.sh /usr/local/bin/capture-entrypoint
RUN chmod +x /usr/local/bin/capture-entrypoint

ENV HOME=/home/netclaw \
    NETCLAW_HOME=/home/netclaw/.netclaw \
    NETCLAW_CONTAINER_SUPERVISOR=entrypoint \
    VHS_NO_SANDBOX=true

WORKDIR /work
ENTRYPOINT ["/usr/local/bin/capture-entrypoint"]
