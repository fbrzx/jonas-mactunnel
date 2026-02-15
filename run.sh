#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load .env file if it exists
if [[ -f "${SCRIPT_DIR}/.env" ]]; then
	set -a
	source "${SCRIPT_DIR}/.env"
	set +a
fi

STATE_DIR="${SCRIPT_DIR}/.oc-tunnel"
PID_FILE="${STATE_DIR}/tunnel.pid"
LOG_FILE="${STATE_DIR}/tunnel.log"

PORT_LOCAL="${PORT_LOCAL:-3000}"
PORT_REMOTE="${PORT_REMOTE:-3000}"
HOST_BIND="${HOST_BIND:-127.0.0.1}"
BROWSER_APP="${BROWSER_APP:-Google Chrome}"

usage() {
	cat <<EOF
Usage: ./run.sh <command>

Commands:
	start         Start SSH tunnel in background and open browser
	start-watch   Start tunnel, open browser app instance, stop tunnel when browser closes
	stop          Stop SSH tunnel
	status        Show tunnel status
	restart       Restart tunnel and open browser

Required env vars:
	KEY_PATH      SSH private key path
	HOST          SSH target (for example: user@bastion)
	TOKEN         Token appended to URL

Optional env vars:
	PORT_LOCAL    Local forwarded port (default: 3000)
	PORT_REMOTE   Remote destination port (default: 3000)
	HOST_BIND     Remote bind host (default: 127.0.0.1)
	BROWSER_APP   Browser app name for start-watch (default: Google Chrome)
EOF
}

is_running() {
	[[ -f "${PID_FILE}" ]] || return 1
	local pid
	pid="$(cat "${PID_FILE}")"
	[[ -n "${pid}" ]] || return 1
	kill -0 "${pid}" 2>/dev/null
}

require_env() {
	local missing=()
	[[ -n "${KEY_PATH:-}" ]] || missing+=("KEY_PATH")
	[[ -n "${HOST:-}" ]] || missing+=("HOST")
	[[ -n "${TOKEN:-}" ]] || missing+=("TOKEN")

	if (( ${#missing[@]} > 0 )); then
		echo "Missing required environment variable(s): ${missing[*]}" >&2
		exit 1
	fi
}

tunnel_url() {
	printf 'http://localhost:%s/#token=%s' "${PORT_LOCAL}" "${TOKEN}"
}

wait_for_tunnel() {
	local retries="${1:-30}"
	local i
	for ((i=1; i<=retries; i++)); do
		if nc -z 127.0.0.1 "${PORT_LOCAL}" >/dev/null 2>&1; then
			return 0
		fi
		sleep 1
	done
	return 1
}

start_tunnel() {
	mkdir -p "${STATE_DIR}"

	if is_running; then
		echo "Tunnel already running (PID $(cat "${PID_FILE}"))."
		return 0
	fi

	echo "Starting tunnel..."
	ssh -i "${KEY_PATH}" \
		-N \
		-L "${PORT_LOCAL}:${HOST_BIND}:${PORT_REMOTE}" \
		-o ExitOnForwardFailure=yes \
		-o ServerAliveInterval=60 \
		-o ServerAliveCountMax=3 \
		"${HOST}" \
		>>"${LOG_FILE}" 2>&1 &

	local pid=$!
	echo "${pid}" > "${PID_FILE}"

	if wait_for_tunnel 20; then
		echo "Tunnel started (PID ${pid})."
	else
		echo "Tunnel did not become ready in time. Check ${LOG_FILE}." >&2
		stop_tunnel || true
		exit 1
	fi
}

stop_tunnel() {
	if ! is_running; then
		rm -f "${PID_FILE}"
		echo "Tunnel is not running."
		return 0
	fi

	local pid
	pid="$(cat "${PID_FILE}")"
	echo "Stopping tunnel (PID ${pid})..."
	kill "${pid}" 2>/dev/null || true

	local i
	for ((i=1; i<=10; i++)); do
		if ! kill -0 "${pid}" 2>/dev/null; then
			rm -f "${PID_FILE}"
			echo "Tunnel stopped."
			return 0
		fi
		sleep 1
	done

	kill -9 "${pid}" 2>/dev/null || true
	rm -f "${PID_FILE}"
	echo "Tunnel force-stopped."
}

open_browser() {
	local url
	url="$(tunnel_url)"
	open "${url}"
	echo "Opened ${url}"
}

start_watch() {
	start_tunnel
	local url
	url="$(tunnel_url)"
	echo "Opening ${BROWSER_APP} and watching for close..."
	open -na "${BROWSER_APP}" -W "${url}"
	echo "Browser closed, stopping tunnel..."
	stop_tunnel
}

status_tunnel() {
	if is_running; then
		echo "Tunnel running (PID $(cat "${PID_FILE}"), localhost:${PORT_LOCAL} -> ${HOST_BIND}:${PORT_REMOTE} via ${HOST})."
	else
		echo "Tunnel stopped."
	fi
}

main() {
	local cmd="${1:-}"

	case "${cmd}" in
		start)
			require_env
			start_tunnel
			open_browser
			;;
		start-watch)
			require_env
			start_watch
			;;
		stop)
			stop_tunnel
			;;
		status)
			status_tunnel
			;;
		restart)
			require_env
			stop_tunnel
			start_tunnel
			open_browser
			;;
		*)
			usage
			exit 1
			;;
	esac
}

main "$@"