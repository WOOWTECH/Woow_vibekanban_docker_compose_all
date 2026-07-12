#!/usr/bin/env bash
# P5: 原生 build vibe-kanban host binary(不進容器),導向自架 remote/relay。
# 含工具鏈安裝(rustup nightly + nvm Node22 + pnpm),全 rootless。
# 系統前置(需 sudo,一次性): apt-get install -y clang libclang-dev
#   —— libsqlite3-sys 的 bindgen 需要 clang dev headers,只有 runtime libclang.so 不夠。
set -euo pipefail
source "$(dirname "$0")/deploy.env"

# ---------- 工具鏈 ----------
if ! command -v rustup >/dev/null 2>&1; then
  echo "== 裝 rustup(rust-toolchain.toml 會自動拉 pinned nightly)=="
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain none
fi
export PATH="$HOME/.cargo/bin:$PATH"

if [ ! -d "$HOME/.nvm" ]; then
  echo "== 裝 nvm =="
  curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
fi
export NVM_DIR="$HOME/.nvm"; . "$NVM_DIR/nvm.sh"
nvm install 22 >/dev/null; nvm use 22 >/dev/null
corepack enable || true
echo "node: $(node -v)  pnpm: $(corepack pnpm -v 2>/dev/null || echo '?')"

cd "$SRC_DIR"

# ---------- patch 1:local-build.sh 寫死 https://api.vibekanban.com,必須改成自架 remote ----------
if grep -q 'api.vibekanban.com' local-build.sh; then
  cp -n local-build.sh local-build.sh.orig
  sed -i "s#https://api.vibekanban.com#$REMOTE_URL#g" local-build.sh
  echo "[patch] local-build.sh base URL -> $REMOTE_URL"
fi

# ---------- patch 2:整包 cargo build 會編 tauri-app 桌面版(headless 缺 glib/GTK 必炸),
#            只 build 需要的三個 bin ----------
if grep -q 'cargo build --release --manifest-path Cargo.toml' local-build.sh; then
  sed -i 's#cargo build --release --manifest-path Cargo.toml#cargo build --release --bin server --bin review --bin vibe-kanban-mcp --manifest-path Cargo.toml#' local-build.sh
  echo "[patch] local-build.sh 只 build server/review/vibe-kanban-mcp(跳過 tauri)"
fi

# ---------- 導向自架(backend runtime + build-time 都吃)----------
export VK_SHARED_API_BASE="$REMOTE_URL"
export VITE_VK_SHARED_API_BASE="$REMOTE_URL"
export VK_SHARED_RELAY_API_BASE="$RELAY_URL"
export LIBCLANG_PATH="${LIBCLANG_PATH:-/usr/lib/llvm-18/lib}"   # bindgen 找 libclang 用(Ubuntu 24.04=llvm-18)

# ---------- build ----------
echo "== pnpm install(root workspace)=="
corepack pnpm install --frozen-lockfile

echo "== local-build.sh(local-web 前端 + Rust release,約 15-40 分)=="
bash local-build.sh

echo "== 產物(npx-cli/dist/<os>-<arch>/)=="
ls -la npx-cli/dist/*/ 2>/dev/null || true
echo "done"
