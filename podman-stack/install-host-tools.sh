#!/bin/bash
set -euo pipefail
# Vibe Kanban Host — Full CLI Tool Installation (Native/Podman)
# Matches K3s deployment tool stack
# Installs to ~/.vibe-kanban-tools/

TOOLS="${HOME}/.vibe-kanban-tools"
BIN="$TOOLS/bin"
VENV="$TOOLS/venv"
MARKER="$TOOLS/.installed-v2"

if [ -f "$MARKER" ]; then
  echo "[SKIP] All tools already installed. Delete $MARKER to force re-install"
  exit 0
fi

echo "Installing CLI tools to $TOOLS"
mkdir -p "$BIN" "$TOOLS/dotnet" "$TOOLS/pw-browsers"

# uv
echo "[1/8] uv..."
[ -f "$BIN/uv" ] || curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR="$BIN" sh

# ffmpeg static
echo "[2/8] ffmpeg..."
if [ ! -f "$BIN/ffmpeg" ]; then
  curl -sL "https://johnvansickle.com/ffmpeg/releases/ffmpeg-release-amd64-static.tar.xz" | \
    tar -xJ --strip-components=1 -C /tmp --wildcards '*/ffmpeg' '*/ffprobe'
  cp /tmp/ffmpeg "$BIN/ffmpeg" && cp /tmp/ffprobe "$BIN/ffprobe" && chmod +x "$BIN/ffmpeg" "$BIN/ffprobe"
fi

# ripgrep
echo "[3/8] ripgrep..."
if ! command -v rg &>/dev/null && [ ! -f "$BIN/rg" ]; then
  curl -sL "https://github.com/BurntSushi/ripgrep/releases/download/14.1.1/ripgrep-14.1.1-x86_64-unknown-linux-musl.tar.gz" | \
    tar -xz --strip-components=1 -C /tmp ripgrep-14.1.1-x86_64-unknown-linux-musl/rg
  cp /tmp/rg "$BIN/rg" && chmod +x "$BIN/rg"
fi

# Python venv via uv
echo "[4/8] Python venv (90+ packages)..."
[ -f "$VENV/bin/python3" ] || "$BIN/uv" venv "$VENV" --python 3.12
"$BIN/uv" pip install --python "$VENV/bin/python3" \
  anthropic openai mcp httpx requests aiohttp websockets \
  fastapi uvicorn starlette pydantic pillow lxml rich click \
  Jinja2 Markdown PyYAML duckduckgo-search playwright \
  beautifulsoup4 html5lib cssselect python-dotenv toml tomli \
  cryptography paramiko jsonschema pyjwt tqdm colorama \
  python-multipart sse-starlette watchfiles orjson ujson \
  typing-extensions annotated-types anyio sniffio certifi \
  charset-normalizer idna urllib3 distro filelock regex \
  tenacity wrapt deprecated attrs cattrs arrow python-dateutil \
  markupsafe pygments numpy pandas

# Playwright Chromium
echo "[5/8] Playwright..."
PLAYWRIGHT_BROWSERS_PATH="$TOOLS/pw-browsers" "$VENV/bin/python3" -m playwright install chromium

# OpenCode
echo "[6/8] OpenCode..."
if [ ! -f "$BIN/opencode" ]; then
  curl -fsSL https://opencode.ai/install | bash -s -- --no-modify-path
  cp "$HOME/.opencode/bin/opencode" "$BIN/opencode" 2>/dev/null || true
fi

# .NET Runtime
echo "[7/8] .NET Runtime..."
[ -f "$TOOLS/dotnet/dotnet" ] || curl -sSL https://dot.net/v1/dotnet-install.sh | bash /dev/stdin \
  --channel 8.0 --runtime dotnet --install-dir "$TOOLS/dotnet" --no-path

# OfficeCLI
echo "[8/8] OfficeCLI..."
[ -f "$BIN/officecli" ] || curl -sL "https://github.com/iOfficeAI/OfficeCLI/releases/download/v1.0.135/officecli-linux-x64" \
  -o "$BIN/officecli" && chmod +x "$BIN/officecli"

echo ""
echo "Done! Add to ~/.bashrc:"
echo "  export PATH=\"$BIN:\$PATH\""
echo "  export PLAYWRIGHT_BROWSERS_PATH=\"$TOOLS/pw-browsers\""
date > "$MARKER"
