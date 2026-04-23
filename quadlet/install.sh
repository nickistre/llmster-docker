#!/usr/bin/env bash
# install.sh — install llmster Quadlet units and build context onto the system.
#
# Overridable via env:
#   SYSCONFDIR  (default /etc)
#   DATADIR     (default /usr/local/share/llmster)
#   QUADLETDIR  (default /etc/containers/systemd)
#   BINDIR      (default /usr/local/bin)
set -euo pipefail

: "${SYSCONFDIR:=/etc}"
: "${DATADIR:=/usr/local/share/llmster}"
: "${QUADLETDIR:=/etc/containers/systemd}"
: "${BINDIR:=/usr/local/bin}"

SRC="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$SRC/.." && pwd)"

confdir="${SYSCONFDIR}/llmster"
buildctx="${DATADIR}/build"

# Read port defaults from the installed env file (first install: fall back to .env.example).
_envfile="${confdir}/llmster.env"
[ -f "$_envfile" ] || _envfile="${REPO}/.env.example"
LLMSTER_PORT="$(grep -m1 '^LLMSTER_PORT=' "$_envfile" | cut -d= -f2)"
CADDY_HTTPS_PORT="$(grep -m1 '^CADDY_HTTPS_PORT=' "$_envfile" | cut -d= -f2)"
: "${LLMSTER_PORT:=1234}"
: "${CADDY_HTTPS_PORT:=1243}"

# ── Directories ──────────────────────────────────────────────────────────────
sudo install -d "$confdir" "$buildctx" "$QUADLETDIR" "$BINDIR"

# ── Build context: Dockerfiles + runtime files ────────────────────────────────
sudo install -m 0644 \
    "$REPO/Dockerfile" \
    "$REPO/Dockerfile.caddy" \
    "$REPO/entrypoint.sh" \
    "$REPO/Caddyfile" \
    "$buildctx/"

# ── Runtime config ────────────────────────────────────────────────────────────
# Always refresh the example so admins can diff for new options.
sudo install -m 0644 "$REPO/.env.example" "$confdir/llmster.env.example"
# Seed the live config only on first install; never overwrite admin edits.
if [ ! -f "$confdir/llmster.env" ]; then
    sudo install -m 0600 "$REPO/.env.example" "$confdir/llmster.env"
    echo "Created $confdir/llmster.env — edit it before starting services."
fi

# ── Quadlet unit templates ────────────────────────────────────────────────────
for tmpl in "$SRC"/*.in; do
    name="$(basename "$tmpl" .in)"
    # Skip script templates — they're handled separately below.
    case "$name" in uninstall.sh) continue ;; esac
    sudo sh -c "sed \
        -e 's|@SYSCONFDIR@|${SYSCONFDIR}|g' \
        -e 's|@DATADIR@|${DATADIR}|g' \
        -e 's|@LLMSTER_PORT@|${LLMSTER_PORT}|g' \
        -e 's|@CADDY_HTTPS_PORT@|${CADDY_HTTPS_PORT}|g' \
        '${tmpl}' > '${QUADLETDIR}/${name}'"
    sudo chmod 0644 "${QUADLETDIR}/${name}"
done

# ── Install llmster-uninstall to BINDIR ───────────────────────────────────────
sudo sh -c "sed \
    -e 's|@SYSCONFDIR@|${SYSCONFDIR}|g' \
    -e 's|@DATADIR@|${DATADIR}|g' \
    -e 's|@QUADLETDIR@|${QUADLETDIR}|g' \
    -e 's|@BINDIR@|${BINDIR}|g' \
    '${SRC}/uninstall.sh.in' > '${BINDIR}/llmster-uninstall'"
sudo chmod 0755 "${BINDIR}/llmster-uninstall"

# ── Activate ──────────────────────────────────────────────────────────────────
sudo systemctl daemon-reload

# Start in dependency order so each layer is ready before the next.
# 1. Network and volumes
sudo systemctl start llm-net-network.service lmstudio-data-volume.service caddy-data-volume.service caddy-config-volume.service

# 2. Build images (may take several minutes on first run)
echo "Building container images (this may take a few minutes on first run)…"
sudo systemctl start llmster-build.service caddy-build.service

# 3. Container services
sudo systemctl start llmster.service caddy.service

echo "Done. Status: systemctl status llmster caddy"
