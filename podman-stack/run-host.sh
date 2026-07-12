#!/usr/bin/env bash
# vibe-kanban host 執行 wrapper(給 systemd user unit 呼叫)。
# 導向自架 remote/relay,並確保 node + claude 在 PATH(host 呼叫 claude 執行 task)。
set -euo pipefail
source "$(dirname "$0")/deploy.env"

export NVM_DIR="$HOME/.nvm"
. "$NVM_DIR/nvm.sh"
nvm use 22 >/dev/null
export PATH="$(dirname "$(nvm which 22)"):$HOME/.cargo/bin:$HOME/.local/bin:$PATH"

# 2026-07-06: 改連 k3s current cluster 的 remote/relay(與 k3s vk-host 同 URL,見 deploy.env HOST_*)
export VK_SHARED_API_BASE="$HOST_REMOTE_URL"
export VK_SHARED_RELAY_API_BASE="$HOST_RELAY_URL"
export HOST="0.0.0.0"          # 與 3100 daily driver 同姿態(tailnet+LAN;host UI 無登入驗證,LAN 需可信)
export PORT="$HOST_PORT"
export BACKEND_PORT="$HOST_PORT"

# ⚠️ 本機關鍵隔離:預設 ~/.local/share/vibe-kanban 屬於 port-3100 的 v0.1.32 daily driver,
#    絕不可共用(schema migration 會弄壞它)。此 host 用獨立資料目錄。
export XDG_DATA_HOME="$VK_XDG_DATA_HOME"
mkdir -p "$XDG_DATA_HOME"

# src 的 cargo build 未完成(build-host.log 中斷),改跑預建 release binary(同 tag v0.1.43,
# 前端 dist 已內嵌;remote URL 由上面 runtime env 決定,前端經 /api/info 取得)
cd "$STACK_DIR"
exec "$HOST_BIN"
