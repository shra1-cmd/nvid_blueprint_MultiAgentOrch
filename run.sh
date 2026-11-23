#!/usr/bin/env bash
# =============================================================================
# Multi-Agent Intelligent Warehouse (MAIW) - Lifecycle Management Script
# Usage: ./run.sh {build|start|stop|restart|status|logs|clean|help}
# =============================================================================
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

RUN_DIR="$ROOT_DIR/.run"
PID_BACKEND="$RUN_DIR/backend.pid"
PID_FRONTEND="$RUN_DIR/frontend.pid"
LOG_BACKEND="$RUN_DIR/backend.log"
LOG_FRONTEND="$RUN_DIR/frontend.log"

BACKEND_PORT="${DEMO_PORT:-8001}"
FRONTEND_PORT="${PORT:-3001}"
PYTHON_BIN=""

if [[ -x "$ROOT_DIR/env/bin/python" ]]; then
  PYTHON_BIN="$ROOT_DIR/env/bin/python"
elif [[ -x "$ROOT_DIR/.venv/bin/python" ]]; then
  PYTHON_BIN="$ROOT_DIR/.venv/bin/python"
fi

mkdir -p "$RUN_DIR"

ensure_env() {
  if [[ ! -f "$ROOT_DIR/.env" ]]; then
    if [[ -f "$ROOT_DIR/../.env" ]]; then
      echo "Copying shared .env from parent directory..."
      cp "$ROOT_DIR/../.env" "$ROOT_DIR/.env"
      chmod 600 "$ROOT_DIR/.env"
    else
      echo "ERROR: .env file not found."
      echo "Create .env with: echo 'NVIDIA_API_KEY=nvapi-...' > .env && chmod 600 .env"
      exit 1
    fi
  fi
  if [[ ! -f "$ROOT_DIR/src/ui/web/.env" && -f "$ROOT_DIR/src/ui/web/.env.example" ]]; then
    cp "$ROOT_DIR/src/ui/web/.env.example" "$ROOT_DIR/src/ui/web/.env"
  fi
}

cmd_build() {
  echo "=================================================="
  echo " Building Multi-Agent Intelligent Warehouse (MAIW)"
  echo "=================================================="
  ensure_env

  # 1. Python virtualenv
  if [[ ! -d "$ROOT_DIR/env" && ! -d "$ROOT_DIR/.venv" ]]; then
    echo "Creating Python virtual environment (env)..."
    python3 -m venv "$ROOT_DIR/env"
    PYTHON_BIN="$ROOT_DIR/env/bin/python"
  fi

  echo "Installing Python requirements..."
  "$PYTHON_BIN" -m pip install --upgrade pip
  "$PYTHON_BIN" -m pip install -r "$ROOT_DIR/requirements.txt"

  echo "Installing MAIW workspace packages (editable)..."
  "$PYTHON_BIN" -m pip install -e "$ROOT_DIR/packages/maiw-contracts" \
                               -e "$ROOT_DIR/packages/maiw-mcp" \
                               -e "$ROOT_DIR/packages/maiw-state" \
                               -e "$ROOT_DIR/packages/maiw-models" \
                               -e "$ROOT_DIR/packages/maiw-skills" \
                               -e "$ROOT_DIR/packages/maiw-decision" \
                               -e "$ROOT_DIR/packages/maiw-execution" \
                               -e "$ROOT_DIR/packages/maiw-agents" \
                               -e "$ROOT_DIR/packages/maiw-world" \
                               -e "$ROOT_DIR/apps/api"

  # 2. Frontend dependencies
  echo "Installing React frontend dependencies..."
  (cd "$ROOT_DIR/src/ui/web" && npm install)

  echo "Verifying environment..."
  "$ROOT_DIR/scripts/check_demo_environment.sh"

  echo "Build complete."
}

is_running() {
  local pid="$1"
  if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
    return 0
  fi
  return 1
}

cmd_start() {
  echo "Starting MAIW services..."
  ensure_env

  if [[ -z "$PYTHON_BIN" || ! -x "$PYTHON_BIN" ]]; then
    echo "Virtual environment not detected. Running build first..."
    cmd_build
  fi

  # Start Backend if not already running
  local b_running=0
  if [[ -f "$PID_BACKEND" ]]; then
    local p
    p="$(cat "$PID_BACKEND" 2>/dev/null || true)"
    if is_running "$p"; then
      b_running=1
      echo "Backend already running (PID: $p, port: $BACKEND_PORT)."
    fi
  fi

  if [[ $b_running -eq 0 ]]; then
    # Check if port is already held
    local port_pids
    port_pids="$(lsof -t -i :"$BACKEND_PORT" -sTCP:LISTEN 2>/dev/null || true)"
    if [[ -n "$port_pids" ]]; then
      echo "Backend port $BACKEND_PORT already in use by PID(s): $port_pids"
      echo "$port_pids" > "$PID_BACKEND"
    else
      echo "Starting Backend API on port $BACKEND_PORT..."
      (
        cd "$ROOT_DIR"
        export DEMO_PORT="$BACKEND_PORT"
        export DEMO_HOST="127.0.0.1"
        nohup "$ROOT_DIR/scripts/start_demo_mode.sh" >> "$LOG_BACKEND" 2>&1 &
        echo $! > "$PID_BACKEND"
      )
    fi
  fi

  # Start Frontend if not already running
  local f_running=0
  if [[ -f "$PID_FRONTEND" ]]; then
    local p
    p="$(cat "$PID_FRONTEND" 2>/dev/null || true)"
    if is_running "$p"; then
      f_running=1
      echo "Frontend already running (PID: $p, port: $FRONTEND_PORT)."
    fi
  fi

  if [[ $f_running -eq 0 ]]; then
    local port_pids
    port_pids="$(lsof -t -i :"$FRONTEND_PORT" -sTCP:LISTEN 2>/dev/null || true)"
    if [[ -n "$port_pids" ]]; then
      echo "Frontend port $FRONTEND_PORT already in use by PID(s): $port_pids"
      echo "$port_pids" > "$PID_FRONTEND"
    else
      echo "Starting Frontend Web UI on port $FRONTEND_PORT..."
      setsid bash -c "cd '$ROOT_DIR/src/ui/web' && PORT='$FRONTEND_PORT' HOST=127.0.0.1 BROWSER=none npx craco start >> '$LOG_FRONTEND' 2>&1" < /dev/null &
      echo $! > "$PID_FRONTEND"
    fi
  fi

  # Wait and verify
  echo "Waiting for services to report ready..."
  for i in {1..30}; do
    if curl -s -m 2 "http://127.0.0.1:$BACKEND_PORT/api/v1/ready" >/dev/null 2>&1 && \
       curl -s -m 2 -I "http://127.0.0.1:$FRONTEND_PORT" >/dev/null 2>&1; then
      break
    fi
    sleep 1
  done

  cmd_status
}

cmd_stop() {
  echo "Stopping MAIW services..."

  # Stop Backend
  if [[ -f "$PID_BACKEND" ]]; then
    local p
    p="$(cat "$PID_BACKEND" 2>/dev/null || true)"
    if [[ -n "$p" ]]; then
      echo "Stopping Backend (PID: $p)..."
      kill "$p" 2>/dev/null || true
    fi
    rm -f "$PID_BACKEND"
  fi
  local p_backend
  p_backend="$(lsof -t -i :"$BACKEND_PORT" -sTCP:LISTEN 2>/dev/null || true)"
  if [[ -n "$p_backend" ]]; then
    kill "$p_backend" 2>/dev/null || true
  fi

  # Stop Frontend
  if [[ -f "$PID_FRONTEND" ]]; then
    local p
    p="$(cat "$PID_FRONTEND" 2>/dev/null || true)"
    if [[ -n "$p" ]]; then
      echo "Stopping Frontend (PID: $p)..."
      kill "$p" 2>/dev/null || true
    fi
    rm -f "$PID_FRONTEND"
  fi
  local p_frontend
  p_frontend="$(lsof -t -i :"$FRONTEND_PORT" -sTCP:LISTEN 2>/dev/null || true)"
  if [[ -n "$p_frontend" ]]; then
    kill "$p_frontend" 2>/dev/null || true
  fi

  sleep 1
  echo "All services stopped."
}

cmd_status() {
  echo "=================================================="
  echo " MAIW Service Status"
  echo "=================================================="

  local b_pid=""
  local f_pid=""
  b_pid="$(lsof -t -i :"$BACKEND_PORT" -sTCP:LISTEN 2>/dev/null | head -n1 || true)"
  f_pid="$(lsof -t -i :"$FRONTEND_PORT" -sTCP:LISTEN 2>/dev/null | head -n1 || true)"

  if [[ -n "$b_pid" ]]; then
    local health
    health="$(curl -s -m 2 "http://127.0.0.1:$BACKEND_PORT/api/v1/ready" | grep -o '"status":"[^"]*"' | head -n1 || echo '"status":"running"')"
    echo "  Backend API : [RUNNING] (PID: $b_pid, port: $BACKEND_PORT, $health)"
    echo "                http://localhost:$BACKEND_PORT"
  else
    echo "  Backend API : [STOPPED] (port $BACKEND_PORT is free)"
  fi

  if [[ -n "$f_pid" ]]; then
    echo "  Frontend UI : [RUNNING] (PID: $f_pid, port: $FRONTEND_PORT)"
    echo "                http://localhost:$FRONTEND_PORT"
  else
    echo "  Frontend UI : [STOPPED] (port $FRONTEND_PORT is free)"
  fi
  echo "=================================================="
}

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

cmd_clean() {
  cmd_stop
  echo "Cleaning log and PID files..."
  rm -rf "$RUN_DIR"
  echo "Clean complete."
}

usage() {
  cat <<'EOF'
Multi-Agent Intelligent Warehouse (MAIW) Manager

Usage:
  ./run.sh start               Start backend API and frontend UI
  ./run.sh stop                Stop both backend and frontend services
  ./run.sh restart             Restart all services
  ./run.sh status              Check status and health of services
  ./run.sh build               Install Python virtualenv, packages, and frontend node_modules
  ./run.sh logs [backend|ui]   Follow logs in real time (default: all)
  ./run.sh clean               Stop services and clean runtime log/pid files
  ./run.sh help                Show this message
EOF
}

action="${1:-help}"
if (($#)); then shift; fi

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
