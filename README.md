# llmster

LM Studio running headless in a container with AMD GPU passthrough, exposing an
OpenAI-compatible API on `http://localhost:1234`.

See `CLAUDE.md` for architecture and environment-variable reference.
Upstream CLI docs: <https://lmstudio.ai/docs/cli>.

## Quick start

```bash
cp .env.example .env
# Edit .env — fill in PROXY_HOST, CLOUDFLARE_API_TOKEN, ACME_EMAIL, LLM_API_KEY
podman compose up -d
podman compose logs -f
curl http://localhost:1234/v1/models
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

The `lms` CLI lives inside the container at `/root/.lmstudio/bin/lms`. Models
and config are stored on the `lmstudio-data` named volume, so downloads
persist across `podman compose down` / `up` (but not `down -v`).

Open a shell in the running container for any of the commands below:

```bash
podman compose exec -it llmster bash
```

### Download a model — `lms get`

Docs: <https://lmstudio.ai/docs/cli/local-models/get>

For an **arbitrary HuggingFace repo**, pass the **full URL**. The short
`user/repo` slug only resolves against LM Studio's curated catalog, so it will
fail with `Failed to resolve artifact ...` for most community repos. Append
`@<quant>` to pin a specific quantization; omit it to pick interactively.

```bash
# Full HF URL + pinned Q8_0 quant (this is the form that works for community repos):
lms get https://huggingface.co/Jackrong/Qwen3.5-9B-Claude-4.6-Opus-Reasoning-Distilled-v2-GGUF@q8_0

# HF URL without a quant — lms prompts you to pick one:
lms get https://huggingface.co/Jackrong/Qwen3.5-9B-Claude-4.6-Opus-Reasoning-Distilled-v2-GGUF

# Curated catalog (staff picks) accepts the short slug:
lms get llama-3.1-8b@q4_k_m
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
lms ls                   # models on disk
lms ps                   # models currently loaded in memory
lms load <key>           # load (supports --gpu=max|auto|0.0-1.0, --context-length=N, --identifier <name>)
lms unload <key>         # unload; --all to unload everything
lms rm <key>             # delete from disk
```

With `JIT_LOADING=true` (the compose default) the first API request
auto-loads the model; `AUTO_UNLOAD` + `UNLOAD_IDLE_TIME` handle eviction, so
you usually don't need `lms load` manually.

### Server + logs

```bash
lms server status        # confirm the server is up
lms server start|stop    # the entrypoint already runs `start` on boot
lms log stream --source server   # tail server logs (entrypoint runs this to keep the container alive)
```

## Use the model via the API

```bash
curl http://localhost:1234/v1/models      # find the model id lms registered

curl http://localhost:1234/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{
    "model": "<id from /v1/models>",
    "messages": [{"role":"user","content":"Say hi."}]
  }'
```

Any OpenAI-compatible client works — point it at `http://llmster:1234/v1`
(from inside the `llm-net` network) or `http://localhost:1234/v1` (from the
host).
