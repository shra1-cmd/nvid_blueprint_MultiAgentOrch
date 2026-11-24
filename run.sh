#!/usr/bin/env bash
# =============================================================================
# Multi-Agent Intelligent Warehouse (MAIW)
# Lifecycle Management Script
#
# Usage:
# ./run.sh {build|start|stop|restart|status|logs|clean|help}
# =============================================================================

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

# =============================================================================
# 1. RUNTIME CONFIGURATION
# =============================================================================

RUN_DIR="$ROOT_DIR/.run"

PID_BACKEND="$RUN_DIR/backend.pid"
PID_FRONTEND="$RUN_DIR/frontend.pid"

LOG_BACKEND="$RUN_DIR/backend.log"
LOG_FRONTEND="$RUN_DIR/frontend.log"

# Persist selected ports
PORT_BACKEND_FILE="$RUN_DIR/backend.port"
PORT_FRONTEND_FILE="$RUN_DIR/frontend.port"

# Default ports
BACKEND_PORT="${DEMO_PORT:-8001}"
FRONTEND_PORT="${PORT:-3001}"

# If no explicit port is supplied, reuse the previously selected port.
if [[ -z "${DEMO_PORT+x}" && -s "$PORT_BACKEND_FILE" ]]; then
    BACKEND_PORT="$(cat "$PORT_BACKEND_FILE")"
fi

if [[ -z "${PORT+x}" && -s "$PORT_FRONTEND_FILE" ]]; then
    FRONTEND_PORT="$(cat "$PORT_FRONTEND_FILE")"
fi

# Maximum ports to search
BACKEND_MAX_PORT=8100
FRONTEND_MAX_PORT=3100

# One interpreter for everything: run.sh and scripts/start_demo_mode.sh
# (the backend launcher) must agree, so it is passed on as DEMO_PYTHON.
PYTHON_BIN=""

if [[ -x "$ROOT_DIR/env/bin/python" ]]; then
    PYTHON_BIN="$ROOT_DIR/env/bin/python"
elif [[ -x "$ROOT_DIR/.venv/bin/python" ]]; then
    PYTHON_BIN="$ROOT_DIR/.venv/bin/python"
fi

# MAIW workspace packages (installed in editable mode).
WORKSPACE_PKGS=(
    packages/maiw-contracts
    packages/maiw-mcp
    packages/maiw-state
    packages/maiw-models
    packages/maiw-skills
    packages/maiw-decision
    packages/maiw-execution
    packages/maiw-agents
    packages/maiw-world
    apps/api
)

mkdir -p "$RUN_DIR"


# =============================================================================
# 2. PORT HELPERS
# =============================================================================

# True if ANY process (any user) is listening on the port.
# `ss` sees every listener; `lsof` without root only sees our own processes,
# which made ports held by other users on this shared server look free.
port_in_use() {

    local port="$1"

    if command -v ss >/dev/null 2>&1; then
        [[ -n "$(ss -ltnH "sport = :$port" 2>/dev/null)" ]]
        return
    fi

    lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1
}

# PID of OUR process listening on the port (empty if none / not ours).
own_listener_pid() {

    local port="$1"

    lsof -t -iTCP:"$port" -sTCP:LISTEN 2>/dev/null | head -n1 || true
}

find_free_port() {

    local start_port="$1"
    local max_port="$2"
    local port

    echo "Searching for a free port from $start_port to $max_port..." >&2

    for ((port=start_port; port<=max_port; port++)); do

        if ! port_in_use "$port"; then

            echo "$port"
            return 0

        fi

        echo "Port $port is occupied. Trying next port..." >&2

    done

    echo "ERROR: No free port available between $start_port and $max_port." >&2
    return 1
}


# =============================================================================
# 3. ENVIRONMENT CONFIGURATION
# =============================================================================

ensure_env() {

    if [[ ! -f "$ROOT_DIR/.env" ]]; then

        if [[ -f "$ROOT_DIR/../.env" ]]; then

            echo "Copying shared .env from parent directory..."

            cp "$ROOT_DIR/../.env" "$ROOT_DIR/.env"
            chmod 600 "$ROOT_DIR/.env"

        else

            echo "ERROR: .env file not found."
            echo "Create .env with NVIDIA_API_KEY."

            exit 1

        fi

    fi

    if [[ ! -f "$ROOT_DIR/src/ui/web/.env" && \
          -f "$ROOT_DIR/src/ui/web/.env.example" ]]; then

        cp "$ROOT_DIR/src/ui/web/.env.example" \
           "$ROOT_DIR/src/ui/web/.env"

    fi
}

install_workspace_pkgs() {

    local extra=("$@")
    local args=()
    local pkg

    for pkg in "${WORKSPACE_PKGS[@]}"; do
        args+=(-e "$ROOT_DIR/$pkg")
    done

    "$PYTHON_BIN" -m pip install "${extra[@]}" "${args[@]}"
}

# Editable installs hard-code the source path. If the project folder is
# moved or renamed they break ("maiw_api package not importable").
# Detect that and re-point them (local packages only, no downloads of deps).
ensure_workspace_pkgs() {

    if ( cd /tmp && "$PYTHON_BIN" -c "import maiw_api" ) >/dev/null 2>&1; then
        return 0
    fi

    echo "MAIW packages not importable (project moved?). Re-linking workspace packages..."

    install_workspace_pkgs -q --no-deps
}


# =============================================================================
# 4. BUILD
# =============================================================================

cmd_build() {

    echo "=================================================="
    echo " Building Multi-Agent Intelligent Warehouse"
    echo "=================================================="

    ensure_env

    # -------------------------------------------------------------------------
    # Python virtual environment
    # -------------------------------------------------------------------------

    if [[ ! -d "$ROOT_DIR/env" && ! -d "$ROOT_DIR/.venv" ]]; then

        echo "Creating Python virtual environment..."

        python3 -m venv "$ROOT_DIR/env"

        PYTHON_BIN="$ROOT_DIR/env/bin/python"

    fi

    echo "Installing Python requirements..."

    "$PYTHON_BIN" -m pip install --upgrade pip

    "$PYTHON_BIN" -m pip install -r "$ROOT_DIR/requirements.txt"

    # -------------------------------------------------------------------------
    # MAIW workspace packages
    # -------------------------------------------------------------------------

    echo "Installing MAIW workspace packages..."

    install_workspace_pkgs

    # -------------------------------------------------------------------------
    # Frontend dependencies
    # -------------------------------------------------------------------------

    echo "Checking React frontend dependencies..."

    if [[ ! -d "$ROOT_DIR/src/ui/web/node_modules" ]]; then

        echo "Frontend dependencies not found. Installing..."

        if [[ -f "$ROOT_DIR/src/ui/web/package-lock.json" ]]; then

            (cd "$ROOT_DIR/src/ui/web" && npm ci)

        else

            (cd "$ROOT_DIR/src/ui/web" && npm install)

        fi

    else

        echo "Frontend node_modules already exists. Skipping installation."

    fi

    # -------------------------------------------------------------------------
    # Environment verification
    # -------------------------------------------------------------------------

    echo "Verifying environment..."

    DEMO_PYTHON="$PYTHON_BIN" "$ROOT_DIR/scripts/check_demo_environment.sh"

    echo "Build complete."
}


# =============================================================================
# 5. PROCESS HELPERS
# =============================================================================

is_running() {

    local pid="$1"

    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
        return 0
    fi

    return 1
}

# Find a running service: first via its pid file, then (if the pid file is
# stale) via one of OUR processes listening on its saved port. Prints the pid
# and refreshes the pid file; prints nothing if the service is not running.
service_pid() {

    local pid_file="$1"
    local port="$2"
    local p=""

    if [[ -f "$pid_file" ]]; then

        p="$(cat "$pid_file" 2>/dev/null || true)"

        if is_running "$p"; then
            echo "$p"
            return 0
        fi

        rm -f "$pid_file"

    fi

    p="$(own_listener_pid "$port")"

    if [[ -n "$p" ]]; then
        echo "$p" > "$pid_file"
        echo "$p"
    fi
}

# Stop a service and its children. The frontend is started with setsid, so
# its pid leads a process group; signal the whole group (bash -> npx -> node).
stop_pid() {

    local p="$1"
    local pgid

    pgid="$(ps -o pgid= -p "$p" 2>/dev/null | tr -d ' ' || true)"

    if [[ -n "$pgid" && "$pgid" == "$p" ]]; then
        kill -- "-$pgid" 2>/dev/null || true
    else
        kill "$p" 2>/dev/null || true
    fi
}


# =============================================================================
# 6. START SERVICES
# =============================================================================

cmd_start() {

    echo "Starting MAIW services..."

    ensure_env

    # -------------------------------------------------------------------------
    # Verify dependencies
    # -------------------------------------------------------------------------

    if [[ -z "$PYTHON_BIN" || ! -x "$PYTHON_BIN" || \
          ! -d "$ROOT_DIR/src/ui/web/node_modules" ]]; then

        echo "Required environment/dependencies missing."
        echo "Running build first..."

        cmd_build

    fi

    ensure_workspace_pkgs


    # =========================================================================
    # BACKEND
    # =========================================================================

    local b_pid

    b_pid="$(service_pid "$PID_BACKEND" "$BACKEND_PORT")"

    if [[ -n "$b_pid" ]]; then

        echo "Backend already running."
        echo "PID: $b_pid"
        echo "Port: $BACKEND_PORT"

    else

        echo ""
        echo "Selecting Backend port..."

        BACKEND_PORT="$(find_free_port "$BACKEND_PORT" "$BACKEND_MAX_PORT")"

        echo "$BACKEND_PORT" > "$PORT_BACKEND_FILE"

        echo "Selected Backend port: $BACKEND_PORT"

        echo "Starting Backend API..."

        (
            cd "$ROOT_DIR"

            export DEMO_PORT="$BACKEND_PORT"
            export DEMO_HOST="127.0.0.1"
            export DEMO_PYTHON="$PYTHON_BIN"

            nohup "$ROOT_DIR/scripts/start_demo_mode.sh" \
                >> "$LOG_BACKEND" 2>&1 &

            echo $! > "$PID_BACKEND"

        )

    fi


    # =========================================================================
    # FRONTEND
    # =========================================================================

    local f_pid

    f_pid="$(service_pid "$PID_FRONTEND" "$FRONTEND_PORT")"

    if [[ -n "$f_pid" ]]; then

        echo "Frontend already running."
        echo "PID: $f_pid"
        echo "Port: $FRONTEND_PORT"
        echo "NOTE: it keeps the proxy target it was started with."
        echo "      If the backend port changed, run: ./run.sh restart"

    else

        echo ""
        echo "Selecting Frontend port..."

        FRONTEND_PORT="$(find_free_port "$FRONTEND_PORT" "$FRONTEND_MAX_PORT")"

        echo "$FRONTEND_PORT" > "$PORT_FRONTEND_FILE"

        echo "Selected Frontend port: $FRONTEND_PORT"

        echo "Starting Frontend Web UI (proxy /api -> 127.0.0.1:$BACKEND_PORT)..."

        # MAIW_API_PROXY_TARGET makes the dev-server proxy (setupProxy.js)
        # follow whatever port the backend actually got.
        setsid bash -c \
            "cd '$ROOT_DIR/src/ui/web' && \
             PORT='$FRONTEND_PORT' \
             MAIW_API_PROXY_TARGET='http://127.0.0.1:$BACKEND_PORT' \
             HOST=127.0.0.1 \
             BROWSER=none \
             npx craco start >> '$LOG_FRONTEND' 2>&1" \
             < /dev/null &

        echo $! > "$PID_FRONTEND"

    fi


    # =========================================================================
    # WAIT FOR SERVICES
    # =========================================================================

    echo ""
    echo "Waiting for services to report ready..."

    local ready=0

    for i in {1..60}; do

        if curl -s -m 2 \
            "http://127.0.0.1:$BACKEND_PORT/api/v1/ready" \
            >/dev/null 2>&1 && \
           curl -s -m 2 -I \
            "http://127.0.0.1:$FRONTEND_PORT" \
            >/dev/null 2>&1; then

            ready=1
            break

        fi

        sleep 1

    done

    if [[ $ready -eq 0 ]]; then

        echo "WARNING: Services did not both become ready within 60 seconds."
        echo "         Check: ./run.sh logs backend | ./run.sh logs frontend"

    fi

    cmd_status
}


# =============================================================================
# 7. STOP SERVICES
# =============================================================================

cmd_stop() {

    echo "Stopping MAIW services..."

    local p

    # -------------------------------------------------------------------------
    # Backend
    # -------------------------------------------------------------------------

    p="$(service_pid "$PID_BACKEND" "$BACKEND_PORT")"

    if [[ -n "$p" ]]; then

        echo "Stopping Backend (PID: $p)..."

        stop_pid "$p"

    fi

    rm -f "$PID_BACKEND"


    # -------------------------------------------------------------------------
    # Frontend
    # -------------------------------------------------------------------------

    p="$(service_pid "$PID_FRONTEND" "$FRONTEND_PORT")"

    if [[ -n "$p" ]]; then

        echo "Stopping Frontend (PID: $p)..."

        stop_pid "$p"

    fi

    rm -f "$PID_FRONTEND"

    sleep 1

    echo "Stop signals sent."

    echo "Selected ports are preserved for the next start."

}


# =============================================================================
# 8. STATUS
# =============================================================================

cmd_status() {

    echo "=================================================="
    echo " MAIW Service Status"
    echo "=================================================="

    local b_pid=""
    local f_pid=""

    b_pid="$(own_listener_pid "$BACKEND_PORT")"

    f_pid="$(own_listener_pid "$FRONTEND_PORT")"


    # Backend status

    if [[ -n "$b_pid" ]]; then

        local health

        health="$(curl -s -m 2 \
            "http://127.0.0.1:$BACKEND_PORT/api/v1/ready" \
            | grep -o '"status":"[^"]*"' \
            | head -n1 || echo '"status":"unknown"')"

        echo " Backend API : [RUNNING]"
        echo " PID         : $b_pid"
        echo " Port        : $BACKEND_PORT"
        echo " Health      : $health"
        echo " URL         : http://localhost:$BACKEND_PORT"

    else

        echo " Backend API : [STOPPED]"
        echo " Port        : $BACKEND_PORT"

    fi


    # Frontend status

    if [[ -n "$f_pid" ]]; then

        local proxy

        proxy="$(curl -s -m 3 -o /dev/null -w '%{http_code}' \
            "http://127.0.0.1:$FRONTEND_PORT/api/v1/ready" || true)"

        echo ""
        echo " Frontend UI : [RUNNING]"
        echo " PID         : $f_pid"
        echo " Port        : $FRONTEND_PORT"
        echo " Proxy /api  : HTTP ${proxy:-000} (200 = reaches backend)"
        echo " URL         : http://localhost:$FRONTEND_PORT"

    else

        echo ""
        echo " Frontend UI : [STOPPED]"
        echo " Port        : $FRONTEND_PORT"

    fi

    echo "=================================================="

}


# =============================================================================
# 9. LOGS
# =============================================================================

cmd_logs() {

    local target="${1:-all}"

    case "$target" in

        backend|api)

            tail -f "$LOG_BACKEND"

            ;;

        frontend|ui)

            tail -f "$LOG_FRONTEND"

            ;;

        all|*)

            tail -f "$LOG_BACKEND" "$LOG_FRONTEND"

            ;;

    esac

}


# =============================================================================
# 10. CLEAN
# =============================================================================

cmd_clean() {

    cmd_stop

    echo "Cleaning runtime files..."

    rm -rf "$RUN_DIR"

    echo "Runtime files and saved ports removed."

    echo "Clean complete."

}


# =============================================================================
# 11. HELP
# =============================================================================

usage() {

    cat <<'EOF'

Multi-Agent Intelligent Warehouse (MAIW) Manager

Usage:

  ./run.sh start               Start backend and frontend
  ./run.sh stop                Stop both services
  ./run.sh restart             Restart both services
  ./run.sh status              Check service status
  ./run.sh build               Install dependencies
  ./run.sh logs backend        Follow backend logs
  ./run.sh logs frontend       Follow frontend logs
  ./run.sh logs                Follow all logs
  ./run.sh clean               Stop and remove runtime files
  ./run.sh help                Show this help

Dynamic Port Configuration:

  Backend:
    Default: 8001
    Search:  8001 - 8100

  Frontend:
    Default: 3001
    Search:  3001 - 3100

  The frontend proxy (/api) is pointed at whichever backend port is
  selected, so a port change never breaks the UI.

Overrides:

  DEMO_PORT=8005 ./run.sh start    Force backend port
  PORT=3005 ./run.sh start         Force frontend port

EOF

}


# =============================================================================
# 12. COMMAND DISPATCHER
# =============================================================================

action="${1:-help}"

if (($#)); then
    shift
fi

case "$action" in

    start)
        cmd_start
        ;;

    stop)
        cmd_stop
        ;;

    restart)
        cmd_stop
        sleep 1
        cmd_start
        ;;

    status)
        cmd_status
        ;;

    build)
        cmd_build
        ;;

    logs)
        cmd_logs "$@"
        ;;

    clean)
        cmd_clean
        ;;

    help|-h|--help)
        usage
        ;;

    *)
        echo "Unknown command: $action" >&2
        usage >&2
        exit 1
        ;;

esac
