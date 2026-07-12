#!/bin/bash
set -euo pipefail
# ============================================================
# Vibe Kanban Host — Full CLI Tool Installation (Native)
# Installs to ~/.vibe-kanban-tools/ for persistence
# Matches the K3s deployment tool stack
# ============================================================

TOOLS="${HOME}/.vibe-kanban-tools"
BIN="$TOOLS/bin"
VENV="$TOOLS/venv"
MARKER="$TOOLS/.installed-v1"

if [ -f "$MARKER" ]; then
  echo "[SKIP] All tools already installed (marker: $MARKER)"
  echo "  Delete $MARKER to force re-install"
  exit 0
fi

echo "============================================"
echo "  Installing CLI tools to $TOOLS"
echo "============================================"
mkdir -p "$BIN" "$TOOLS/dotnet" "$TOOLS/pw-browsers"

# --- [1] uv (Python package manager) ---
echo "[1/7] uv..."
if [ ! -f "$BIN/uv" ]; then
  curl -LsSf https://astral.sh/uv/install.sh | env CARGO_HOME=/tmp/cargo UV_INSTALL_DIR="$BIN" sh
fi
echo "  uv: $($BIN/uv --version)"

# --- [2] ffmpeg (static binary) ---
echo "[2/7] ffmpeg (static)..."
if [ ! -f "$BIN/ffmpeg" ]; then
  curl -sL "https://johnvansickle.com/ffmpeg/releases/ffmpeg-release-amd64-static.tar.xz" | \
    tar -xJ --strip-components=1 -C /tmp --wildcards '*/ffmpeg' '*/ffprobe'
  cp /tmp/ffmpeg "$BIN/ffmpeg" && chmod +x "$BIN/ffmpeg"
  cp /tmp/ffprobe "$BIN/ffprobe" && chmod +x "$BIN/ffprobe"
fi
echo "  ffmpeg: $($BIN/ffmpeg -version 2>&1 | head -1)"

# --- [3] ripgrep (if not already on system) ---
echo "[3/7] ripgrep..."
if ! command -v rg &>/dev/null && [ ! -f "$BIN/rg" ]; then
  curl -sL "https://github.com/BurntSushi/ripgrep/releases/download/14.1.1/ripgrep-14.1.1-x86_64-unknown-linux-musl.tar.gz" | \
    tar -xz --strip-components=1 -C /tmp ripgrep-14.1.1-x86_64-unknown-linux-musl/rg
  cp /tmp/rg "$BIN/rg" && chmod +x "$BIN/rg"
fi
echo "  rg: $(rg --version 2>&1 | head -1 || $BIN/rg --version 2>&1 | head -1)"

# --- [4] Python venv via uv ---
echo "[4/7] Python venv (90+ packages)..."
if [ ! -f "$VENV/bin/python3" ]; then
  "$BIN/uv" venv "$VENV" --python 3.12
fi
"$BIN/uv" pip install --python "$VENV/bin/python3" \
  anthropic openai mcp \
  httpx requests aiohttp websockets \
  fastapi uvicorn starlette \
  pydantic pillow lxml \
  rich click Jinja2 Markdown PyYAML \
  duckduckgo-search playwright \
  beautifulsoup4 html5lib cssselect \
  python-dotenv toml tomli \
  cryptography paramiko jsonschema pyjwt \
  tqdm colorama python-multipart \
  sse-starlette watchfiles orjson ujson \
  typing-extensions annotated-types anyio sniffio \
  certifi charset-normalizer idna urllib3 distro filelock \
  regex tenacity wrapt deprecated attrs cattrs \
  arrow python-dateutil markupsafe pygments numpy pandas
echo "  Python packages installed"

# --- [5] Playwright + Chromium ---
echo "[5/7] Playwright Chromium..."
PLAYWRIGHT_BROWSERS_PATH="$TOOLS/pw-browsers" "$VENV/bin/python3" -m playwright install chromium
echo "  Playwright: $($VENV/bin/playwright --version)"

# --- [6] OpenCode ---
echo "[6/7] OpenCode..."
if [ ! -f "$BIN/opencode" ]; then
  curl -fsSL https://opencode.ai/install | bash -s -- --no-modify-path
  cp "$HOME/.opencode/bin/opencode" "$BIN/opencode" 2>/dev/null || true
fi
echo "  OpenCode: $($BIN/opencode --version 2>&1 || $HOME/.opencode/bin/opencode --version 2>&1)"

# --- [7] .NET Runtime ---
echo "[7/7] .NET Runtime..."
if [ ! -f "$TOOLS/dotnet/dotnet" ]; then
  curl -sSL https://dot.net/v1/dotnet-install.sh | bash /dev/stdin \
    --channel 8.0 --runtime dotnet --install-dir "$TOOLS/dotnet" --no-path
fi
echo "  .NET: installed"

# --- PATH setup ---
echo ""
echo "============================================"
echo "  Installation complete!"
echo ""
echo "  Add to your shell profile (~/.bashrc):"
echo "    export PATH=\"$BIN:\$PATH\""
echo "    export PLAYWRIGHT_BROWSERS_PATH=\"$TOOLS/pw-browsers\""
echo "    export DOTNET_ROOT=\"$TOOLS/dotnet\""
echo "    export VIRTUAL_ENV=\"$VENV\""
echo "============================================"

date > "$MARKER"
