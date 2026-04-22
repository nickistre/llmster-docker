# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Purpose

This project deploys LM Studio in headless server mode ("llmster") inside a container with AMD GPU support. The server exposes an OpenAI-compatible API on port 1234, intended to serve local LLMs to other services (e.g., AnythingLLM).

## Common Commands

```bash
# Build the container image
podman build -f Dockerfile.llmster -t llmster .

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

## Architecture

**Single service** (`llmster`) defined in `docker-compose.yaml`:
- Base image: `debian:trixie-slim`
- Installs LM Studio via `lmstudio.ai/install.sh` at **image build time** (fallback) and again at **every container start** (`entrypoint.sh`) to stay current
- If the startup install fails (network unavailable), the entrypoint logs a warning and continues with the baked-in install — the server still starts
- Adds Mesa Vulkan drivers (`mesa-vulkan-drivers`) for AMD GPU access
- Traps SIGTERM/SIGINT for clean daemon/server shutdown
- Health check hits `GET /v1/models` on port 1234

**GPU access** requires host device passthrough:
- `/dev/dri` — DRM/KMS (Mesa/Vulkan rendering)
- `/dev/kfd` — ROCm kernel driver
- `/dev/fuse` — FUSE filesystem (used by LM Studio AppImage internals)

**Persistent storage**: the named volume `lmstudio-data` is mounted at `/root/.lmstudio`, covering binaries, runtime, config, and models. A fresh volume is seeded from the image's baked-in install on first run. Models survive `podman compose down` but are wiped by `podman compose down -v`.

**Key environment variables** (set in both Dockerfile defaults and compose overrides):
| Variable | Purpose |
|---|---|
| `LLMSTER_PORT` | API listen port (default 1234) |
| `LMS_SERVER_HOST` | Bind address (set to `0.0.0.0` for container access) |
| `OLLAMA_ORIGINS` | CORS origins (`*` allows AnythingLLM to connect) |
| `JIT_LOADING` | Load model on first request instead of startup |
| `AUTO_UNLOAD` | Unload model after idle |
| `UNLOAD_IDLE_TIME` | Seconds before auto-unload (default 300) |
| `LIBVA_DRIVER_NAME` | VA-API driver (`radeonsi` for AMD) |

**Network**: compose stack uses `llm-net` bridge network; AnythingLLM (or other clients) should join this network and connect to `llmster:1234`.

## Notes

- Resource limits (CPU/memory) are commented out in compose; uncomment and tune based on available hardware.
- `pull_policy: build` means compose always builds from the Dockerfile rather than pulling from a registry; the `pull: true` inside the `build:` block keeps the base `debian:trixie-slim` image fresh.
