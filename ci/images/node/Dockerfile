# ci-node: the shared Linux toolchain image. Every other CI image builds FROM it.
# Holds the Actions runner plus the JS toolchain (Node, Bun, gh). Nothing secret is baked in.
# Base pinned by digest; the weekly rebuild still picks up security fixes via apt-get upgrade.
FROM ubuntu:24.04@sha256:534baea6a22c03a63003dbc8dbe78fe34bc0d7e595d9a9dc9834884ff530eb55

ARG RUNNER_VERSION=2.338.0
ARG RUNNER_SHA256=af4b794c1bc41d73d40535e3fe092a39f9679cd8d965954c2aca25a05ca41d32
ARG NODE_VERSION=24.21.0
ARG BUN_VERSION=1.3.12
ARG GH_KEY_FINGERPRINT=2C6106201985B60E6C7AC87323F3D4EA75716059

ENV DEBIAN_FRONTEND=noninteractive LANG=C.UTF-8

RUN apt-get update && apt-get -y upgrade && apt-get install -y --no-install-recommends \
      ca-certificates curl git jq unzip zip xz-utils rsync file tini procps \
      build-essential python3 openssh-client gnupg util-linux \
    && install -d -m 0755 /etc/apt/keyrings \
    && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg -o /etc/apt/keyrings/githubcli.gpg \
    && gpg --show-keys --with-colons /etc/apt/keyrings/githubcli.gpg | grep -q "^fpr:::::::::${GH_KEY_FINGERPRINT}:" \
    && echo "deb [signed-by=/etc/apt/keyrings/githubcli.gpg] https://cli.github.com/packages stable main" > /etc/apt/sources.list.d/github-cli.list \
    && apt-get update && apt-get install -y --no-install-recommends gh \
    && rm -rf /var/lib/apt/lists/*

# Node, verified against the release's SHASUMS256.txt
RUN cd /tmp && f="node-v${NODE_VERSION}-linux-x64.tar.xz" \
    && curl -fsSLO "https://nodejs.org/dist/v${NODE_VERSION}/${f}" \
    && curl -fsSL "https://nodejs.org/dist/v${NODE_VERSION}/SHASUMS256.txt" | grep " ${f}\$" | sha256sum -c - \
    && tar -xJf "$f" -C /usr/local --strip-components=1 --exclude='*.md' --exclude=LICENSE \
    && rm "$f"

# Bun, verified against the release's SHASUMS256.txt
RUN cd /tmp && base="https://github.com/oven-sh/bun/releases/download/bun-v${BUN_VERSION}" \
    && curl -fsSLO "${base}/bun-linux-x64.zip" \
    && curl -fsSL "${base}/SHASUMS256.txt" | grep " bun-linux-x64.zip\$" | sha256sum -c - \
    && unzip -q bun-linux-x64.zip && install -m 0755 bun-linux-x64/bun /usr/local/bin/bun \
    && ln -s bun /usr/local/bin/bunx && rm -rf bun-linux-x64*

# Actions runner, verified against the pinned SHA. Jobs run as the unprivileged "runner" user.
RUN useradd --create-home --uid 1001 --shell /bin/bash runner \
    && install -d -o runner -g runner /opt/runner /work \
    && cd /opt/runner \
    && curl -fsSL -o runner.tgz "https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz" \
    && echo "${RUNNER_SHA256}  runner.tgz" | sha256sum -c - \
    && tar xzf runner.tgz && rm runner.tgz \
    && ./bin/installdependencies.sh && rm -rf /var/lib/apt/lists/* \
    && chown -R runner:runner /opt/runner

# Caches live on per-trust-tier volumes mounted under /cache (see ci-platform).
ENV BUN_INSTALL_CACHE_DIR=/cache/bun \
    npm_config_cache=/cache/npm \
    ELECTRON_CACHE=/cache/electron \
    electron_config_cache=/cache/electron \
    ELECTRON_BUILDER_CACHE=/cache/electron-builder \
    GRADLE_USER_HOME=/cache/gradle \
    RUNNER_TOOL_CACHE=/cache/toolcache \
    AGENT_TOOLSDIRECTORY=/cache/toolcache

COPY entrypoint.sh /opt/ci/entrypoint.sh
COPY hooks/ /opt/ci/hooks/
RUN chmod 0755 /opt/ci/entrypoint.sh /opt/ci/hooks/*.sh

# Starts as container root (an unprivileged host user under rootless Docker) to fix volume
# ownership, stage secrets and police the one-job rule; job code only ever runs as "runner".
ENTRYPOINT ["/usr/bin/tini", "--", "/opt/ci/entrypoint.sh"]
