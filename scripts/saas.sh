#!/usr/bin/env bash
# scripts/saas.sh — one-command launcher for the Inspector SaaS
# Usage:
#   ./scripts/saas.sh up    — ensure postgres is up, build binary if missing, launch server, open browser
#   ./scripts/saas.sh down  — stop the server (kills background sleuth-saas)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="${REPO_ROOT}/docker/compose.yaml"
BIN="${REPO_ROOT}/bin/sleuth-saas"
PORT=8932
PID_FILE="/tmp/sleuth-saas.pid"

cmd="${1:-up}"

case "${cmd}" in
  up)
    echo "[saas] Ensuring postgres container is running..."
    if docker compose version &>/dev/null; then
        docker compose -f "${COMPOSE_FILE}" up -d postgres
    else
        docker-compose -f "${COMPOSE_FILE}" up -d postgres
    fi

    echo "[saas] Waiting for postgres to be healthy..."
    for i in $(seq 1 30); do
      STATUS="$(docker inspect --format='{{.State.Health.Status}}' sleuth-postgres 2>/dev/null || echo 'missing')"
      if [ "${STATUS}" = "healthy" ]; then
        echo "[saas] postgres is healthy."
        break
      fi
      if [ "${i}" -eq 30 ]; then
        echo "[saas] ERROR: postgres did not become healthy within 30s" >&2
        exit 1
      fi
      sleep 1
    done

    if [ ! -x "${BIN}" ]; then
      echo "[saas] bin/sleuth-saas not found — building..."
      "${REPO_ROOT}/scripts/build-saas.sh"
    else
      echo "[saas] bin/sleuth-saas already present — skipping build."
    fi

    if [ -f "${PID_FILE}" ]; then
      OLD_PID="$(cat "${PID_FILE}")"
      if kill -0 "${OLD_PID}" 2>/dev/null; then
        echo "[saas] sleuth-saas already running (pid ${OLD_PID}). Stop with: $0 down"
        exit 0
      fi
      rm -f "${PID_FILE}"
    fi

    echo "[saas] Launching sleuth-saas on port ${PORT}..."
    "${BIN}" &
    SAAS_PID=$!
    echo "${SAAS_PID}" > "${PID_FILE}"
    echo "[saas] pid ${SAAS_PID} written to ${PID_FILE}"

    sleep 2

    if ! kill -0 "${SAAS_PID}" 2>/dev/null; then
      echo "[saas] ERROR: sleuth-saas exited immediately — check logs above" >&2
      rm -f "${PID_FILE}"
      exit 1
    fi

    echo "[saas] sleuth-saas is up at http://127.0.0.1:${PORT}/"

    if command -v xdg-open &>/dev/null && [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]; then
      xdg-open "http://127.0.0.1:${PORT}/" </dev/null &>/dev/null &
    elif command -v open &>/dev/null; then
      open "http://127.0.0.1:${PORT}/" </dev/null &>/dev/null &
    else
      echo "[saas] Open your browser at http://127.0.0.1:${PORT}/"
    fi
    ;;

  down)
    if [ -f "${PID_FILE}" ]; then
      SAAS_PID="$(cat "${PID_FILE}")"
      if kill -0 "${SAAS_PID}" 2>/dev/null; then
        echo "[saas] Stopping sleuth-saas (pid ${SAAS_PID})..."
        kill "${SAAS_PID}"
        rm -f "${PID_FILE}"
        echo "[saas] stopped."
      else
        echo "[saas] PID ${SAAS_PID} is not running — cleaning up pid file."
        rm -f "${PID_FILE}"
      fi
    else
      echo "[saas] No pid file found — nothing to stop."
    fi
    ;;

  *)
    echo "Usage: $0 {up|down}" >&2
    exit 1
    ;;
esac
