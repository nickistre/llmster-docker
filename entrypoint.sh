#!/bin/sh
set -e

LMS_BIN=/root/.lmstudio/bin/lms

if [ "${LM_STUDIO_UPDATE:-0}" = "1" ]; then
    echo "[entrypoint] attempting to refresh LM Studio install..."
    if curl -fsSL --max-time 30 https://lmstudio.ai/install.sh | sh; then
        echo "[entrypoint] install refresh succeeded"
    else
        echo "[entrypoint] WARNING: install refresh failed; continuing with existing install" >&2
    fi
else
    echo "[entrypoint] LM_STUDIO_UPDATE=0; skipping install refresh"
fi

if [ ! -x "$LMS_BIN" ]; then
    echo "[entrypoint] FATAL: $LMS_BIN missing and no fallback available" >&2
    exit 1
fi

SETTINGS=/root/.lmstudio/settings.json
mkdir -p "$(dirname "$SETTINGS")"
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
tmp="$(mktemp -p "$(dirname "$SETTINGS")")"
jq --argjson ttl "${JIT_TTL_SECONDS:-3600}" '
  .developer.jitModelTTL = { enabled: true, ttlSeconds: $ttl } |
  .developer.unloadPreviousJITModelOnLoad = true
' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
echo "[entrypoint] settings.json: jitModelTTL.ttlSeconds=${JIT_TTL_SECONDS:-3600}, JIT+unload forced on"

if [ "${LMS_RUNTIME_UPDATE:-0}" = "1" ]; then
    echo "[entrypoint] attempting to update lms runtimes..."
    if "$LMS_BIN" runtime update; then
        echo "[entrypoint] runtime update succeeded"
    else
        echo "[entrypoint] WARNING: runtime update failed; continuing with existing runtimes" >&2
    fi
else
    echo "[entrypoint] LMS_RUNTIME_UPDATE=0; skipping runtime update"
fi

trap '"$LMS_BIN" server stop; "$LMS_BIN" daemon down' TERM INT
"$LMS_BIN" daemon up
"$LMS_BIN" server start --port "${LLMSTER_PORT:-1234}"
"$LMS_BIN" log stream --source server
