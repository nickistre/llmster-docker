# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Purpose

This project deploys LM Studio in headless server mode ("llmster") inside a container with AMD GPU support. The server exposes an OpenAI-compatible API on port 1234, intended to serve local LLMs to other services (e.g., AnythingLLM).

## Common Commands

### Ad-hoc (docker compose)
```bash
# Build the container image
podman build -f Dockerfile -t llmster .

# Start the stack (detached)
podman compose up -d
# or
docker compose up -d

# View live logs
podman compose logs -f llmster

# Stop and remove containers
podman compose down

# Rebuild and restart
podman compose up -d --build

# Check health / API
curl http://localhost:1234/v1/models
```

### Systemd via Quadlet (production)
```bash
# Install / update Quadlet units and start services (run once, then after changes)
# Edit /etc/llmster/llmster.env (created on first run) before starting services.
sudo quadlet/install.sh

# View logs
journalctl -u llmster -f
journalctl -u caddy -f

# Start / stop / restart individual services
sudo systemctl start llmster
sudo systemctl stop llmster
sudo systemctl restart llmster

# Check service status
systemctl status llmster caddy

# Uninstall (preserves /etc/llmster/llmster.env and Podman volumes)
sudo llmster-uninstall

# Uninstall and remove all data including downloaded models
sudo llmster-uninstall --purge
```

**Installed paths:**
| Path | Contents |
|---|---|
| `/etc/llmster/llmster.env` | Runtime config (edit this) |
| `/etc/llmster/llmster.env.example` | Reference / upgrade diff |
| `/usr/local/share/llmster/build/` | Build context (Dockerfiles, entrypoint, Caddyfile) |
| `/etc/containers/systemd/` | Generated Quadlet units |
| `/usr/local/bin/llmster-uninstall` | Uninstaller |

## Architecture

**Single service** (`llmster`) defined in `docker-compose.yaml`:
- Base image: `debian:trixie-slim`
- Installs LM Studio via `lmstudio.ai/install.sh` at **image build time** (fallback) and again at **every container start** (`entrypoint.sh`) to stay current
- If the startup install fails (network unavailable), the entrypoint logs a warning and continues with the baked-in install — the server still starts
- Adds Mesa Vulkan drivers (`mesa-vulkan-drivers`) for AMD GPU access
- Traps SIGTERM/SIGINT for clean daemon/server shutdown
- Health check hits `GET /v1/models` on `$LLMSTER_PORT` (default 1234)
- At startup, `entrypoint.sh` patches `~/.lmstudio/settings.json` with `jq` to force JIT loading on and apply `$JIT_TTL_SECONDS`. LM Studio has no env-var or CLI interface for these settings; patching the JSON is the only way to configure them headlessly.

**GPU access** requires host device passthrough:
- `/dev/dri` — DRM/KMS (Mesa/Vulkan rendering)
- `/dev/kfd` — ROCm kernel driver
- `/dev/fuse` — FUSE filesystem (used by LM Studio AppImage internals)

**Persistent storage**: the named volume `lmstudio-data` is mounted at `/root/.lmstudio`, covering binaries, runtime, config, and models. A fresh volume is seeded from the image's baked-in install on first run. Models survive `podman compose down` but are wiped by `podman compose down -v`.

**Key environment variables** (set in `.env.example` / compose / Quadlet env file):
| Variable | Purpose |
|---|---|
| `LLMSTER_PORT` | API listen port, passed via `--port` to `lms server start` (default 1234) |
| `CADDY_HTTPS_PORT` | Host port Caddy binds for HTTPS (default 1243) |
| `JIT_TTL_SECONDS` | Seconds an idle JIT-loaded model stays in memory (default 3600); written to `settings.json` at startup |
| `LMS_SERVER_HOST` | Bind address (set to `0.0.0.0` for container access) |
| `OLLAMA_ORIGINS` | CORS origins (`*` allows AnythingLLM to connect) |
| `LIBVA_DRIVER_NAME` | VA-API driver (`radeonsi` for AMD) |
| `LM_STUDIO_UPDATE` | Set to `1` to re-download LM Studio on every start |
| `LMS_RUNTIME_UPDATE` | Set to `1` to run `lms runtime update` on every start |

**Quadlet port changes** require re-running `sudo quadlet/install.sh` — Quadlet `PublishPort=` is resolved at install time from the env file, not at container runtime.

**Network**: compose stack uses `llm-net` bridge network; AnythingLLM (or other clients) should join this network and connect to `llmster:1234`.

## Notes

- Resource limits (CPU/memory) are commented out in compose; uncomment and tune based on available hardware.
- `pull_policy: build` means compose always builds from the Dockerfile rather than pulling from a registry; the `pull: true` inside the `build:` block keeps the base `debian:trixie-slim` image fresh.
