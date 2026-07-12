#!/usr/bin/env bash
# P2: build remote-server 與 relay-server image(rootless podman)。
# 「v2 法」:前端在主機原生 build(繞開 buildah 對 node:alpine fe-builder 階段
# workspace 子路徑 exports 解析失敗的 bug:@vibe/ui/components/* 解析不到),
# Dockerfile 只 COPY 現成 dist;Rust 階段仍在容器內。
# 實戰驗證:Ubuntu 24.04 + podman 4.9.3 + podman-compose 1.0.6。
set -euo pipefail
source "$(dirname "$0")/deploy.env"

cd "$SRC_DIR"
export NVM_DIR="$HOME/.nvm"; . "$NVM_DIR/nvm.sh"; nvm use 22 >/dev/null
corepack enable >/dev/null 2>&1 || true

# 1) 原生 build remote-web,relay URL 烤進前端(build-time bake,事後改 env 無效;改域名=重 build)
export VITE_RELAY_API_BASE_URL="$RELAY_URL"
echo "== 原生 build remote-web (relay=$RELAY_URL) =="
corepack pnpm install --frozen-lockfile 2>&1 | tail -3
corepack pnpm -C packages/remote-web build 2>&1 | tail -6
test -f packages/remote-web/dist/index.html || { echo "!! dist build FAILED"; exit 1; }
grep -rl "$RELAY_DOMAIN" packages/remote-web/dist >/dev/null 2>&1 \
  && echo "[ok] relay URL 已烤進 dist" \
  || echo "[warn] dist 內找不到 relay URL 字串(續行,部署後驗 bundle)"

# 2) 產 self-host Dockerfile:移除 fe-builder 階段,改 COPY 現成 dist
python3 - <<'PY'
p="crates/remote/Dockerfile"
lines=open(p).read().splitlines()
out=[]; skip=False
for line in lines:
    if line.startswith("FROM node:") and "fe-builder" in line:
        skip=True; continue
    if skip and line.startswith("FROM rust:"):
        skip=False
    if skip: continue
    if line.strip().startswith("COPY --from=fe-builder"):
        out.append("COPY packages/remote-web/dist /srv/static"); continue
    out.append(line)
open("crates/remote/Dockerfile.selfhost","w").write("\n".join(out)+"\n")
print("[ok] 產生 crates/remote/Dockerfile.selfhost")
PY

# 2b) 自架不需私有 billing repo(FEATURES 空時 Dockerfile 自動剝 billing crate),
#     移除 --mount=type=ssh 避免 buildah 要求 ssh agent
sed -i '/--mount=type=ssh/d' crates/remote/Dockerfile.selfhost

# 3) 自訂 ignorefile:根 .dockerignore 會排掉 dist/,必須繞開它保留 dist
cat > crates/remote/dockerignore.selfhost <<'IGN'
**/node_modules
**/target
.git
IGN

echo "== podman build remote-server(prebuilt dist;首次 15-40 分)=="
podman build \
  --file crates/remote/Dockerfile.selfhost \
  --ignorefile crates/remote/dockerignore.selfhost \
  --tag "localhost/vibe-kanban-remote:${IMAGE_TAG}" \
  .

echo "== podman build relay-server(純 Rust,官方 Dockerfile 直接可用)=="
podman build \
  --file crates/relay-tunnel/Dockerfile \
  --tag "localhost/vibe-kanban-relay:${IMAGE_TAG}" \
  .

echo "==== done ===="
podman images | grep -E 'vibe-kanban-(remote|relay)'
