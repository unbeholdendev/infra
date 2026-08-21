FROM debian:bookworm-slim

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl git \
    && rm -rf /var/lib/apt/lists/*
    
ARG FJMCP_VERSION=2.30.2
RUN set -o pipefail && curl -sSfL "https://codeberg.org/goern/forgejo-mcp/releases/download/v${FJMCP_VERSION}/forgejo-mcp_${FJMCP_VERSION}_linux_amd64.tar.gz" \
    | tar -xz -C /usr/local/bin --strip-components=1 "forgejo-mcp_${FJMCP_VERSION}_linux_amd64/forgejo-mcp"

RUN git config --system user.name "agent" \
  && git config --system user.email "335420059+unbeholdendev@users.noreply.github.com" \
  && git config --system credential.helper \
     '!f() { echo username=agent; echo "password=$(cat "$HOME/.forgejo-token")"; }; f'

RUN pipx install --include-deps ansible \
    && pipx install ansible-lint

WORKDIR /root

RUN curl -fsSL https://claude.ai/install.sh | bash
ENV PATH="/root/.local/bin:${PATH}"