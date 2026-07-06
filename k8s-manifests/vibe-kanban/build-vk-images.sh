#!/bin/bash
set -euo pipefail

# ============================================================
# Vibe Kanban K3s — Image Build Script
# Builds 3 container images and imports into K3s containerd
# ============================================================

VK_REPO="/home/woowtechcluster1/vibe-kanban-remote"
IMAGE_VERSION="v0.1.43"

CYAN='\033[0;36m'; GREEN='\033[0;32m'; RED='\033[0;31m'; NC='\033[0m'
info()  { echo -e "${CYAN}[INFO]${NC} $1"; }
ok()    { echo -e "${GREEN}[OK]${NC} $1"; }
fail()  { echo -e "${RED}[FAIL]${NC} $1"; exit 1; }

echo "============================================================"
echo "  Vibe Kanban — Image Build Pipeline"
echo "  Version: ${IMAGE_VERSION}"
echo "============================================================"

# ---- Step 1: Build vk-remote image ----
info "Building vk-remote:${IMAGE_VERSION}..."
REMOTE_BUILD=$(mktemp -d)
# Use pre-built v0.1.44 remote binary (functionally identical to v0.1.43)
cp "${VK_REPO}/runtime-image/remote" "${REMOTE_BUILD}/remote"
# Use v0.1.43 rebuilt frontend (with correct relay URL baked in)
cp -r "${VK_REPO}/packages/remote-web/dist" "${REMOTE_BUILD}/static"

cat > "${REMOTE_BUILD}/Dockerfile" <<'EOF'
FROM docker.io/library/ubuntu:24.04
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates libssl3 wget \
 && rm -rf /var/lib/apt/lists/* \
 && useradd --system --create-home --uid 1100 appuser
WORKDIR /srv
COPY remote /usr/local/bin/remote
RUN chmod +x /usr/local/bin/remote
COPY static /srv/static
USER appuser
ENV SERVER_LISTEN_ADDR=0.0.0.0:8081 RUST_LOG=info,remote=info
EXPOSE 8081
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD ["wget","--spider","-q","http://127.0.0.1:8081/v1/health"]
ENTRYPOINT ["/usr/local/bin/remote"]
EOF
podman build -t "vk-remote:${IMAGE_VERSION}" "${REMOTE_BUILD}"
rm -rf "${REMOTE_BUILD}"
ok "vk-remote:${IMAGE_VERSION} built"

# ---- Step 2: Build vk-relay image ----
info "Building vk-relay:${IMAGE_VERSION}..."
RELAY_BUILD=$(mktemp -d)
cp "${VK_REPO}/relay-image/relay-server" "${RELAY_BUILD}/relay-server"

cat > "${RELAY_BUILD}/Dockerfile" <<'EOF'
FROM docker.io/library/ubuntu:24.04
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates libssl3 wget \
 && rm -rf /var/lib/apt/lists/* \
 && useradd --system --create-home --uid 1100 appuser
COPY relay-server /usr/local/bin/relay-server
RUN chmod +x /usr/local/bin/relay-server
USER appuser
ENV RELAY_LISTEN_ADDR=0.0.0.0:8082 RUST_LOG=info,relay=info
EXPOSE 8082
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD ["wget","--spider","-q","http://127.0.0.1:8082/health"]
ENTRYPOINT ["/usr/local/bin/relay-server"]
EOF
podman build -t "vk-relay:${IMAGE_VERSION}" "${RELAY_BUILD}"
rm -rf "${RELAY_BUILD}"
ok "vk-relay:${IMAGE_VERSION} built"

# ---- Step 3: Build vk-host image ----
info "Building vk-host:${IMAGE_VERSION}..."
HOST_BUILD=$(mktemp -d)

# Host binary must be built from v0.1.43 source
if [ ! -f "${VK_REPO}/target/release/server" ]; then
  fail "Host binary not found. Run 'cargo build --release --bin server' in ${VK_REPO} first."
fi
cp "${VK_REPO}/target/release/server" "${HOST_BUILD}/server"

cat > "${HOST_BUILD}/Dockerfile" <<'EOF'
FROM node:22-bookworm-slim
RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    ca-certificates curl git openssh-client tini wget libssl3 procps \
  && rm -rf /var/lib/apt/lists/*
RUN npm install -g @anthropic-ai/claude-code
RUN ARCH=$(dpkg --print-architecture) && \
    OPENCODE_VERSION=$(curl -sL https://api.github.com/repos/opencode-ai/opencode/releases/latest | \
      grep '"tag_name"' | sed -E 's/.*"v([^"]+)".*/\1/') && \
    echo "Installing OpenCode v${OPENCODE_VERSION} for ${ARCH}" && \
    curl -sLo /usr/local/bin/opencode \
      "https://github.com/opencode-ai/opencode/releases/download/v${OPENCODE_VERSION}/opencode_${OPENCODE_VERSION}_linux_${ARCH}" && \
    chmod +x /usr/local/bin/opencode
RUN useradd --system --create-home --uid 10001 --shell /bin/bash appuser
COPY server /usr/local/bin/server
RUN chmod +x /usr/local/bin/server
RUN mkdir -p /var/tmp/vibe-kanban && chown -R appuser:appuser /home/appuser /var/tmp/vibe-kanban
USER appuser
WORKDIR /home/appuser
RUN git config --global user.email "vk-host@woowtech.io" && \
    git config --global user.name "VK Host"
ENV RUST_LOG=info
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/server"]
EOF
podman build -t "vk-host:${IMAGE_VERSION}" "${HOST_BUILD}"
rm -rf "${HOST_BUILD}"
ok "vk-host:${IMAGE_VERSION} built"

# ---- Step 4: Import into K3s containerd ----
info "Importing images into K3s containerd..."
for IMG in "vk-remote:${IMAGE_VERSION}" "vk-relay:${IMAGE_VERSION}" "vk-host:${IMAGE_VERSION}"; do
  info "  Importing ${IMG}..."
  podman save "localhost/${IMG}" | sudo k3s ctr images import -
done
ok "All images imported into K3s."

echo ""
echo "============================================================"
ok "All 3 Vibe Kanban images built and imported!"
echo "  vk-remote:${IMAGE_VERSION}"
echo "  vk-relay:${IMAGE_VERSION}"
echo "  vk-host:${IMAGE_VERSION}"
echo "============================================================"
