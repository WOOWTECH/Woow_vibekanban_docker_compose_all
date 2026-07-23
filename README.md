<p align="center">
  <img src="docs/screenshots/05-host-ui.png" alt="Vibe Kanban K3s" width="720"/>
</p>

<h1 align="center">Woow Vibe Kanban — K3s Deployment</h1>

<p align="center">
  <strong>Complete Self-Hosted Vibe Kanban on K3s/Kubernetes</strong><br/>
  8 Services · 3 Sidecar Containers · MCP Server · OpenChamber · Web Terminal
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Vibe_Kanban-v0.1.43-blue" alt="VK"/>
  <img src="https://img.shields.io/badge/OpenCode-v1.18.4-green" alt="OpenCode"/>
  <img src="https://img.shields.io/badge/MCP-33_Tools-purple" alt="MCP"/>
  <img src="https://img.shields.io/badge/OpenChamber-Web_GUI-orange" alt="OpenChamber"/>
  <a href="README_zh-TW.md">中文</a>
</p>

---

## Architecture

```mermaid
graph TB
    subgraph Internet
        User[Browser]
        Agent[AI Agent]
    end
    subgraph CF[Cloudflare Tunnel - 7 routes]
        CFD[cloudflared]
    end
    subgraph K3s[K3s Namespace: vibe-kanban]
        DB[(PostgreSQL 16)]
        Remote[Remote Server :8081]
        Electric[ElectricSQL :3000]
        Relay[Relay Server :8082]
        subgraph HostPod[Pod: vk-host - 3 containers]
            Host[host :3000<br/>VK Server + CLI Tools]
            MCP[mcp-service :8080/:8000<br/>33 MCP Tools + Admin GUI]
            OC[openchamber :3080<br/>OpenCode Web GUI]
        end
        Terminal[ttyd :7681<br/>Web Terminal]
    end
    User --> CFD
    Agent --> CFD
    CFD --> Remote & Relay & Host & MCP & OC & Terminal
    Remote --> DB
    Electric --> DB
    Relay --> DB
    Host --> Remote & Relay
    MCP -->|localhost| Host
    Terminal -.->|kubectl exec| Host
```

## Components

| Pod | Container(s) | Ports | Purpose |
|-----|-------------|-------|---------|
| vk-db | postgres | 5432 | PostgreSQL 16 (wal_level=logical) |
| vk-remote | remote | 8081 | Web UI + REST API |
| vk-electric | electric | 3000 | Real-time sync (ElectricSQL 1.4.13) |
| vk-relay | relay | 8082 | Host connection relay |
| **vk-host** | **host** | 3000 | VK Host Server + 50 CLI tools |
| | **mcp-service** | 8080, 8000 | MCP Admin + Supergateway (33 tools) |
| | **openchamber** | 3080 | OpenCode Web GUI (OpenChamber) |
| vk-terminal | ttyd | 7681 | Browser-based shell |
| vk-cloudflared | cloudflared | — | CF Tunnel (7 routes) |

## External URLs

| Service | URL |
|---------|-----|
| Remote (Web UI) | `woowtechkxs-vibekanban.woowtech.io` |
| Relay | `woowtechkxs-vibekanban-relay.woowtech.io` |
| Host UI | `woowtechkxs-vibekanban-host.woowtech.io` |
| Terminal | `woowtechkxs-vibekanban-terminal.woowtech.io` |
| MCP Admin | `woowtechkxs-vibekanban-mcp.woowtech.io` |
| OpenChamber | `woowtechkxs-vibekanban-opencode.woowtech.io` |
| MCP Direct | `woowtechkxs-vk-mcp.woowtech.io/mcp` |

## CLI Tools (Host Container)

| Tool | Version | Type |
|------|---------|------|
| Claude Code | 2.1.201 | AI Agent |
| OpenCode | 1.18.4 | AI Agent |
| OfficeCLI | 1.0.136 | Document Automation |
| ffmpeg/ffprobe | 7.0.2 | Multimedia |
| ripgrep | 14.1.1 | Search |
| Playwright + Chromium | 1.61.0 | Browser Automation |
| uv | 0.11.28 | Python Package Manager |
| .NET Runtime | 8.0.28 | Runtime |
| Python venv (92 pkgs) | anthropic/openai/mcp/fastapi/numpy/pandas | Libraries |

## Key Features (since initial release)

- **OpenChamber sidecar** — Full OpenCode Web GUI with chat, Git, voice mode
- **MCP Service sidecar** — 33 VK tools via StreamableHttp, token auth, admin GUI
- **Shared OpenCode config** — OpenChamber and Host share same config via PVC
- **Persistent ~/.local** — profiles.json, auth, DB survive restarts
- **OpenCode v1.18.4** — base_command_override in profiles.json
- **Dotfile fix** — OPENCHAMBER_DIST_DIR workaround for SPA 404
- **50 CLI tools** — all persisted on NFS PVC via initContainer

## Deploy

```bash
kubectl apply -f k8s-manifests/vibe-kanban/
```

See individual manifest files for configuration details.

---

<p align="center"><sub>Built by <a href="https://github.com/WOOWTECH">WOOWTECH</a></sub></p>
