# llmster

LM Studio running headless in a container with AMD GPU passthrough, exposing an
OpenAI-compatible API on `http://localhost:1234`.

See `CLAUDE.md` for architecture and environment-variable reference.
Upstream CLI docs: <https://lmstudio.ai/docs/cli>.

## Quick start (ad-hoc / dev)

```bash
cp .env.example .env
# Edit .env — fill in PROXY_HOST, CLOUDFLARE_API_TOKEN, ACME_EMAIL, LLM_API_KEY
podman compose up -d
podman compose logs -f
curl http://localhost:1234/v1/models
```

## Run under systemd (Quadlet — recommended for production)

Quadlet units in `quadlet/` let systemd manage the containers so they start
automatically at boot without any manual `compose up`.

**One-time setup:**

> [!NOTE]
> The build steps pull base images from Docker Hub. Unauthenticated pulls are
> rate-limited and may fail on a cold system if the limit is reached. To avoid
> this, [create a free Docker Hub account](https://hub.docker.com/signup) and
> log in before running the installer:
> ```bash
> sudo podman login docker.io
> ```
> See the [Podman login docs](https://docs.podman.io/en/latest/markdown/podman-login.1.html)
> for details.

```bash
sudo quadlet/install.sh
# On first run, /etc/llmster/llmster.env is created from .env.example.
# Edit it now — fill in PROXY_HOST, CLOUDFLARE_API_TOKEN, ACME_EMAIL, and LLM_API_KEY.
# Adjust LLMSTER_PORT, CADDY_HTTPS_PORT, and JIT_TTL_SECONDS if needed.
sudo nano /etc/llmster/llmster.env

# Then restart the services to pick up your changes:
sudo systemctl restart llmster caddy
```

After any config change, restart the affected service:

```bash
sudo systemctl restart llmster   # after changing LLMSTER_PORT, JIT_TTL_SECONDS, etc.
sudo systemctl restart caddy     # after changing CADDY_HTTPS_PORT, LLM_API_KEY, etc.
```

> [!NOTE]
> Changing `LLMSTER_PORT` or `CADDY_HTTPS_PORT` also requires re-running
> `sudo quadlet/install.sh` to update the `PublishPort=` lines in the generated
> systemd units, followed by `sudo systemctl daemon-reload` and a service restart.

`install.sh` renders the `.in` templates to `/etc/containers/systemd/`, copies
the build context (Dockerfiles, entrypoint, Caddyfile) to `/usr/local/share/llmster/build/`,
installs `llmster-uninstall` to `/usr/local/bin/`, and reloads systemd's generator.
After that, services come up on every boot automatically.

**Installed paths:**

| Path | Contents |
|---|---|
| `/etc/llmster/llmster.env` | Runtime config — edit this |
| `/etc/llmster/llmster.env.example` | Reference; updated on each `install.sh` run |
| `/usr/local/share/llmster/build/` | Build context for Quadlet `.build` units |
| `/etc/containers/systemd/` | Generated Quadlet units |
| `/usr/local/bin/llmster-uninstall` | Uninstaller |

**Day-to-day commands:**

```bash
systemctl status llmster caddy          # check service state
journalctl -u llmster -f                # live llmster logs
sudo systemctl restart llmster          # restart after config changes
```

**Re-run `quadlet/install.sh` any time you update the repo** — it is idempotent.

**Uninstall** (config and volumes are preserved by default):

```bash
sudo llmster-uninstall             # remove units + build context
sudo llmster-uninstall --purge     # also remove config and all Podman volumes (destroys models)
```

**Custom install prefix** (for packaging or non-standard layouts):

```bash
SYSCONFDIR=/etc DATADIR=/usr/local/share/llmster QUADLETDIR=/etc/containers/systemd BINDIR=/usr/local/bin \
  sudo -E quadlet/install.sh
```

Two endpoints are available:

| Endpoint | Auth required | Use case |
|---|---|---|
| `http://localhost:1234/v1` | No | Local / trusted network access |
| `https://<PROXY_HOST>:1243/v1` | Bearer token | Remote / external access |

## HTTPS proxy (Caddy)

The `caddy` service terminates TLS and enforces Bearer token auth before
proxying to `llmster:1234`. It uses Cloudflare DNS-01 to obtain a Let's
Encrypt certificate, so port 80 never needs to be open.

**Required `.env` values:**

| Variable | Description |
|---|---|
| `PROXY_HOST` | Hostname Caddy serves (must be in a Cloudflare-managed zone) |
| `CLOUDFLARE_API_TOKEN` | Token with Zone:Read + DNS:Edit — create at dash.cloudflare.com/profile/api-tokens |
| `ACME_EMAIL` | Let's Encrypt account email |
| `LLM_API_KEY` | Bearer token clients send in `Authorization: Bearer <key>` — generate with `openssl rand -hex 32` |

Clients connect on port `1243` (HTTPS):

```bash
curl https://<PROXY_HOST>:1243/v1/models \
  -H "Authorization: Bearer <LLM_API_KEY>"
```

## Managing models with `lms`

The `lms` CLI lives inside the container. Models and config are stored on the
`lmstudio-data` named volume, so downloads persist across `podman compose down`
/ `up` (but not `down -v`).

Run `lms` commands directly via `podman exec`. Under Quadlet (systemd), prefix
with `sudo` since the containers run as root:

```bash
# Compose
podman exec llmster lms <command>

# Quadlet / systemd
sudo podman exec llmster lms <command>
```

For an interactive shell if you need it:

```bash
podman exec -it llmster bash       # compose
sudo podman exec -it llmster bash  # Quadlet / systemd
```

### Login — `lms login`

Authenticate with your LM Studio account (required for some catalog features):

```bash
podman exec llmster lms login
```

### Download a model — `lms get`

Docs: <https://lmstudio.ai/docs/cli/local-models/get>

For an **arbitrary HuggingFace repo**, pass the **full URL**. The short
`user/repo` slug only resolves against LM Studio's curated catalog, so it will
fail with `Failed to resolve artifact ...` for most community repos. Append
`@<quant>` to pin a specific quantization; omit it to pick interactively.

```bash
# Full HF URL + pinned Q8_0 quant (this is the form that works for community repos):
podman exec llmster lms get https://huggingface.co/Jackrong/Qwen3.5-9B-Claude-4.6-Opus-Reasoning-Distilled-v2-GGUF@q8_0

# HF URL without a quant — lms prompts you to pick one:
podman exec llmster lms get https://huggingface.co/Jackrong/Qwen3.5-9B-Claude-4.6-Opus-Reasoning-Distilled-v2-GGUF

# Curated catalog (staff picks) accepts the short slug:
podman exec llmster lms get llama-3.1-8b@q4_k_m
```

`lms get` always asks for confirmation before writing to disk:

```
   ↓ To download: Qwen3.5 9B Q8_0 [GGUF] - 10.45 GB

About to download 10.45 GB.

✔ Start download? yes
```

Useful flags:

- `--gguf` / `--mlx` — restrict results to a format
- `-a, --always-show-download-options` — force the quant picker even when a
  quant is already specified
- `-n, --limit <N>` — cap search results when browsing
- `--always-show-all-results` — show the selection prompt even on exact matches

### List, load, unload, remove

```bash
podman exec llmster lms ls                   # models on disk
podman exec llmster lms ps                   # models currently loaded in memory
podman exec llmster lms load <key>           # load (supports --gpu=max|auto|0.0-1.0, --context-length=N, --identifier <name>)
podman exec llmster lms unload <key>         # unload; --all to unload everything
podman exec llmster lms rm <key>             # delete from disk
```

JIT loading is always enabled — the first API request auto-loads the model.
`JIT_TTL_SECONDS` (default 3600) controls how long an idle model stays in
memory before being evicted.

### Server + logs

```bash
podman exec llmster lms server status                    # confirm the server is up
podman exec llmster lms server start|stop               # the entrypoint already runs `start` on boot
podman exec llmster lms log stream --source server      # tail server logs (the entrypoint runs this to keep the container alive)
```

## Use the model via the API

```bash
curl http://localhost:${LLMSTER_PORT:-1234}/v1/models      # find the model id lms registered

curl http://localhost:${LLMSTER_PORT:-1234}/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{
    "model": "<id from /v1/models>",
    "messages": [{"role":"user","content":"Say hi."}]
  }'
```

Any OpenAI-compatible client works — point it at `http://llmster:1234/v1`
(from inside the `llm-net` network) or `http://localhost:1234/v1` (from the
host, using the default port).
