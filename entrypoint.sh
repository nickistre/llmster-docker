#!/bin/sh
set -e

LMS_BIN=/root/.lmstudio/bin/lms

echo "[entrypoint] attempting to refresh LM Studio install..."
if curl -fsSL --max-time 30 https://lmstudio.ai/install.sh | sh; then
    echo "[entrypoint] install refresh succeeded"
else
    echo "[entrypoint] WARNING: install refresh failed; continuing with existing install" >&2
fi

if [ ! -x "$LMS_BIN" ]; then
    echo "[entrypoint] FATAL: $LMS_BIN missing and no fallback available" >&2
    exit 1
fi

trap '"$LMS_BIN" server stop; "$LMS_BIN" daemon down' TERM INT
"$LMS_BIN" daemon up
"$LMS_BIN" server start
tail -f /dev/null &
wait $!
