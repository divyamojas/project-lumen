#!/bin/bash

# Lumen — Local stack orchestrator
# Usage:
#   ./start.sh                 Start the stack
#   ./start.sh --rebuild       Clean, rebuild, and start the stack
#   ./start.sh --clean         Stop the stack and remove project data
#   ./start.sh --down          Stop the stack
#   ./start.sh --status        Show compose status
#   ./start.sh --logs          Follow all compose logs
#   ./start.sh --logs=app      Follow logs for one service
#   ./start.sh --doctor        Run environment checks only
#   ./start.sh --help          Show usage

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_PARENT_DIR="$(cd "$ROOT_DIR/.." && pwd)"
ROOT_REPO_NAME="project-lumen"
FRONTEND_REPO_NAME="project-lumen-light"
BACKEND_REPO_NAME="project-lumen-source"
DEFAULT_BRANCH="${PROJECT_LUMEN_DEFAULT_BRANCH:-main}"
ROOT_REPO_URL="${PROJECT_LUMEN_ROOT_REPO_URL:-https://github.com/divyamojas/project-lumen.git}"
FRONTEND_REPO_URL="${PROJECT_LUMEN_FRONTEND_REPO_URL:-https://github.com/divyamojas/project-lumen-light.git}"
BACKEND_REPO_URL="${PROJECT_LUMEN_BACKEND_REPO_URL:-https://github.com/divyamojas/project-lumen-source.git}"

FRONTEND_DIR="$ROOT_DIR/$FRONTEND_REPO_NAME"
BACKEND_DIR="$ROOT_DIR/$BACKEND_REPO_NAME"
BACKEND_ENV_FILE="$BACKEND_DIR/.env"
BACKEND_ENV_EXAMPLE_FILE="$BACKEND_DIR/.env.example"
FRONTEND_CADDYFILE="$FRONTEND_DIR/Caddyfile"
FRONTEND_DOCKERFILE="$FRONTEND_DIR/Dockerfile"
BACKEND_DOCKERFILE="$BACKEND_DIR/Dockerfile"

COMPOSE_CMD=(docker compose)
COMPOSE_GLOBAL_ARGS=()
COMPOSE_UP_ARGS=()
LOG_DIR="$ROOT_DIR/logs"
LOG_FILE="$LOG_DIR/lumen-$(date +%Y-%m-%dT%H-%M-%S).log"
TAIL_PID_FILE="$LOG_DIR/.tail.pid"
STARTUP_FAILED=false
VERBOSE=false
ORIGINAL_ARGS=("$@")

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

ACTION="start"
BUILD_FLAG=""
FULL_CLEAN=false
LOGS_SERVICE=""

print_usage() {
  cat <<EOF
Usage: ./start.sh [option]

Options:
  --rebuild      Clean, rebuild, and start the stack
  --clean        Stop the stack and remove project volumes
  --down         Stop all Lumen services
  --status       Show compose status for the Lumen stack
  --logs         Follow logs for all services
  --logs=NAME    Follow logs for a specific service (app, proxy, api)
  --doctor       Run preflight checks and bootstrap missing repos
  --help         Show this help text
  --verbose      Print docker and git commands before running them

Bootstrap behavior:
  If the root repo or sibling repos are missing, the script fetches them
  automatically. If a repo exists without .git metadata, the script sets up
  a local git repo and adds the expected origin remote without fetching full
  history on every run.
EOF
}

log() {
  mkdir -p "$LOG_DIR" > /dev/null 2>&1 || true
  echo "[$(date +%Y-%m-%dT%H:%M:%S)] $1" >> "$LOG_FILE"
}

say() {
  echo -e "$1"
  log "$(echo -e "$1" | sed 's/\x1b\[[0-9;]*m//g')"
}

fail() {
  say "${RED}ERROR: $1${NC}"
  exit 1
}

run_compose() {
  if [ "$VERBOSE" = true ]; then
    say "${YELLOW}→ ${COMPOSE_CMD[*]} ${COMPOSE_GLOBAL_ARGS[*]} $*${NC}"
  fi

  cd "$ROOT_DIR" && "${COMPOSE_CMD[@]}" "${COMPOSE_GLOBAL_ARGS[@]}" "$@"
}

run_git() {
  if [ "$VERBOSE" = true ]; then
    say "${YELLOW}→ git $*${NC}"
  fi

  git "$@"
}

stop_log_tails() {
  if [ -f "$TAIL_PID_FILE" ]; then
    while IFS= read -r pid; do
      kill "$pid" 2>/dev/null || true
    done < "$TAIL_PID_FILE"
    rm -f "$TAIL_PID_FILE"
  fi
}

cleanup_on_interrupt() {
  stop_log_tails
  if [ "$STARTUP_FAILED" = true ]; then
    say "${YELLOW}Interrupted during startup. Leaving partial containers in place for debugging.${NC}"
  fi
  exit 130
}

require_command() {
  local command_name="$1"
  local help_text="$2"

  if ! command -v "$command_name" > /dev/null 2>&1; then
    fail "$help_text"
  fi
}

parse_args() {
  local arg=""

  for arg in "$@"; do
    case "$arg" in
      --rebuild)
        ACTION="start"
        BUILD_FLAG="--build"
        FULL_CLEAN=true
        ;;
      --clean)
        ACTION="clean"
        FULL_CLEAN=true
        ;;
      --down)
        ACTION="down"
        ;;
      --status)
        ACTION="status"
        ;;
      --doctor)
        ACTION="doctor"
        ;;
      --help)
        ACTION="help"
        ;;
      --logs)
        ACTION="logs"
        ;;
      --logs=*)
        ACTION="logs"
        LOGS_SERVICE="${arg#--logs=}"
        ;;
      --verbose)
        VERBOSE=true
        ;;
      *)
        fail "Unknown option: $arg\nRun ./start.sh --help for supported options."
        ;;
    esac
  done
}

root_layout_present_at() {
  local dir="$1"

  [ -f "$dir/docker-compose.yml" ] && [ -f "$dir/start.sh" ] && [ -f "$dir/README.md" ]
}

repo_is_git() {
  local dir="$1"

  git -C "$dir" rev-parse --is-inside-work-tree > /dev/null 2>&1
}

dir_is_empty() {
  local dir="$1"

  [ -z "$(find "$dir" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]
}

ensure_git_origin() {
  local dir="$1"
  local url="$2"
  local label="$3"
  local current_origin=""

  require_command git "Git is required to bootstrap the Lumen repositories."

  if ! repo_is_git "$dir"; then
    say "${YELLOW}$label exists without git metadata. Initializing a local git repo...${NC}"
    run_git -C "$dir" init -q || fail "Failed to initialize git in $dir"
    run_git -C "$dir" branch -M "$DEFAULT_BRANCH" > /dev/null 2>&1 || true
  fi

  current_origin="$(git -C "$dir" remote get-url origin 2>/dev/null || true)"
  if [ -z "$current_origin" ]; then
    run_git -C "$dir" remote add origin "$url" || fail "Failed to set origin for $label"
  elif [ "$current_origin" != "$url" ]; then
    say "${YELLOW}Warning: $label origin is $current_origin, expected $url. Leaving the existing remote unchanged.${NC}"
  fi
}

clone_repo() {
  local dir="$1"
  local url="$2"
  local label="$3"

  require_command git "Git is required to bootstrap the Lumen repositories."

  say "${YELLOW}$label not found. Cloning it now...${NC}"
  run_git clone --depth 1 "$url" "$dir" || fail "Failed to clone $label from $url"
}

ensure_repo_checkout() {
  local dir="$1"
  local url="$2"
  local label="$3"
  local required_file="$4"

  if [ -e "$dir" ] && [ ! -d "$dir" ]; then
    fail "$label path exists but is not a directory: $dir"
  fi

  if [ ! -d "$dir" ]; then
    clone_repo "$dir" "$url" "$label"
  elif [ ! -f "$required_file" ]; then
    if dir_is_empty "$dir"; then
      clone_repo "$dir" "$url" "$label"
    else
      fail "$label exists at $dir but is missing $(basename "$required_file"). Move it aside or restore the repo contents."
    fi
  fi

  ensure_git_origin "$dir" "$url" "$label"
}

bootstrap_root_repo_if_needed() {
  local target_dir="$ROOT_PARENT_DIR/$ROOT_REPO_NAME"

  if root_layout_present_at "$ROOT_DIR"; then
    return 0
  fi

  require_command git "Git is required to bootstrap the Lumen repositories."

  if [ "$ROOT_DIR" = "$target_dir" ]; then
    target_dir="$ROOT_PARENT_DIR/${ROOT_REPO_NAME}-bootstrap"
  fi

  if [ -d "$target_dir" ] && ! root_layout_present_at "$target_dir"; then
    fail "Root repo files are missing in $ROOT_DIR and the bootstrap target $target_dir is not a valid $ROOT_REPO_NAME checkout."
  fi

  if [ ! -d "$target_dir" ]; then
    say "${YELLOW}Root repo files are missing here. Bootstrapping $ROOT_REPO_NAME into $target_dir...${NC}"
    run_git clone --depth 1 "$ROOT_REPO_URL" "$target_dir" || fail "Failed to bootstrap $ROOT_REPO_NAME from $ROOT_REPO_URL"
  fi

  chmod +x "$target_dir/start.sh" 2>/dev/null || true
  say "${YELLOW}Re-running from bootstrapped repo: $target_dir${NC}"
  exec "$target_dir/start.sh" "${ORIGINAL_ARGS[@]}"
}

seed_backend_env_if_missing() {
  if [ -f "$BACKEND_ENV_FILE" ]; then
    return 0
  fi

  if [ -f "$BACKEND_ENV_EXAMPLE_FILE" ]; then
    cp "$BACKEND_ENV_EXAMPLE_FILE" "$BACKEND_ENV_FILE" || fail "Failed to create $BACKEND_ENV_FILE from .env.example"
    say "${YELLOW}Created $BACKEND_ENV_FILE from .env.example. Fill in real values to enable the API.${NC}"
  fi
}

backend_repo_present() {
  [ -d "$BACKEND_DIR" ] && [ -f "$BACKEND_DOCKERFILE" ]
}

backend_env_ready() {
  local required_keys=(
    SUPABASE_URL
    SUPABASE_SECRET_KEY
    SUPABASE_PUBLISHABLE_KEY
    DATABASE_URL
  )
  local key=""

  if [ ! -f "$BACKEND_ENV_FILE" ]; then
    return 1
  fi

  for key in "${required_keys[@]}"; do
    if ! grep -Eq "^${key}=.+" "$BACKEND_ENV_FILE"; then
      return 1
    fi
  done

  return 0
}

backend_can_start() {
  backend_repo_present && backend_env_ready
}

print_backend_state() {
  if backend_can_start; then
    say "  Backend profile: enabled"
  elif backend_repo_present; then
    say "${YELLOW}  Backend profile: skipped until $BACKEND_ENV_FILE has real values for the required keys${NC}"
  else
    say "${YELLOW}  Backend profile: skipped ($BACKEND_REPO_NAME not found)${NC}"
  fi
}

bootstrap_project_layout() {
  bootstrap_root_repo_if_needed
  ensure_git_origin "$ROOT_DIR" "$ROOT_REPO_URL" "$ROOT_REPO_NAME"
  ensure_repo_checkout "$FRONTEND_DIR" "$FRONTEND_REPO_URL" "$FRONTEND_REPO_NAME" "$FRONTEND_DOCKERFILE"
  ensure_repo_checkout "$BACKEND_DIR" "$BACKEND_REPO_URL" "$BACKEND_REPO_NAME" "$BACKEND_DOCKERFILE"
  seed_backend_env_if_missing
}

check_docker() {
  require_command docker "Docker is not installed or not on PATH."

  if ! docker info > /dev/null 2>&1; then
    fail "Docker is not running. Start Docker Desktop and try again."
  fi

  if ! docker compose version > /dev/null 2>&1; then
    fail "docker compose not available. Update Docker Desktop to a version that includes the compose plugin."
  fi
}

check_frontend_files() {
  if [ ! -d "$FRONTEND_DIR" ]; then
    fail "Frontend not found at $FRONTEND_DIR"
  fi

  if [ ! -f "$FRONTEND_DOCKERFILE" ]; then
    fail "Frontend Dockerfile not found at $FRONTEND_DOCKERFILE"
  fi

  if [ ! -f "$FRONTEND_CADDYFILE" ]; then
    fail "Caddyfile not found at $FRONTEND_CADDYFILE"
  fi
}

check_backend_files() {
  if ! backend_repo_present; then
    fail "Backend repo is missing required files at $BACKEND_DIR"
  fi
}

configure_compose_flags() {
  local mode="$1"

  COMPOSE_GLOBAL_ARGS=()
  COMPOSE_UP_ARGS=()

  if [ "$mode" = "manage" ]; then
    if backend_can_start; then
      COMPOSE_GLOBAL_ARGS+=(--profile api)
    fi
  elif backend_can_start; then
    COMPOSE_GLOBAL_ARGS+=(--profile api)
  fi

  if [ -n "$BUILD_FLAG" ]; then
    COMPOSE_UP_ARGS+=("$BUILD_FLAG")
  fi
}

teardown_stack() {
  local saved_args=("${COMPOSE_GLOBAL_ARGS[@]}")
  local down_args=(down)

  stop_log_tails
  rm -f "$TAIL_PID_FILE"
  configure_compose_flags manage
  if [ "$FULL_CLEAN" = true ]; then
    down_args+=(--volumes --remove-orphans)
  fi
  run_compose "${down_args[@]}" 2>/dev/null || true
  COMPOSE_GLOBAL_ARGS=("${saved_args[@]}")
}

port_owned_by_lumen() {
  local host_port="$1"
  local service=""
  local container_port=""
  local published=""

  case "$host_port" in
    3000)
      service="app"
      container_port="3000"
      ;;
    80)
      service="proxy"
      container_port="80"
      ;;
    443)
      service="proxy"
      container_port="443"
      ;;
    8000)
      service="api"
      container_port="8000"
      ;;
    *)
      return 1
      ;;
  esac

  if [ "$service" = "api" ] && ! backend_can_start; then
    return 1
  fi

  published=$(run_compose port "$service" "$container_port" 2>/dev/null || true)
  if [ -z "$published" ]; then
    return 1
  fi

  echo "$published" | grep -Eq "(^|:)${host_port}$"
}

check_ports() {
  local ports_to_check=(3000 80 443)
  local port=""

  require_command lsof "lsof is required for port checks."

  if backend_can_start; then
    ports_to_check+=(8000)
  fi

  for port in "${ports_to_check[@]}"; do
    if lsof -nP -iTCP:"$port" -sTCP:LISTEN > /dev/null 2>&1; then
      if port_owned_by_lumen "$port"; then
        continue
      fi
      fail "Port $port is already in use. Stop the conflicting process and try again.\n  Find it with: lsof -nP -iTCP:$port -sTCP:LISTEN"
    fi
  done
}

doctor() {
  mkdir -p "$LOG_DIR"
  bootstrap_project_layout
  configure_compose_flags start

  say "${GREEN}Lumen doctor — running preflight checks...${NC}"
  check_docker
  check_frontend_files
  check_backend_files
  check_ports
  say "${GREEN}Doctor check passed.${NC}"
  print_backend_state
}

wait_for_url() {
  local label="$1"
  local url="$2"
  local timeout_seconds="$3"
  local curl_args=("${@:4}")
  local deadline=$((SECONDS + timeout_seconds))
  local next_progress=5
  local elapsed=0

  require_command curl "curl is required for readiness checks."

  while [ "$SECONDS" -lt "$deadline" ]; do
    if curl "${curl_args[@]}" "$url" > /dev/null 2>&1; then
      say "${GREEN}      $label ready.${NC}"
      return 0
    fi

    elapsed=$((timeout_seconds - (deadline - SECONDS)))
    if [ "$elapsed" -ge "$next_progress" ]; then
      say "${YELLOW}      Waiting for $label... ${elapsed}s/${timeout_seconds}s${NC}"
      next_progress=$((next_progress + 5))
    fi
    sleep 1
  done

  return 1
}

wait_for_proxy() {
  local timeout_seconds="$1"
  local deadline=$((SECONDS + timeout_seconds))
  local next_progress=5
  local elapsed=0

  while [ "$SECONDS" -lt "$deadline" ]; do
    if run_compose exec -T proxy wget -q --spider --no-check-certificate https://127.0.0.1 > /dev/null 2>&1; then
      say "${GREEN}      HTTPS proxy ready.${NC}"
      return 0
    fi

    elapsed=$((timeout_seconds - (deadline - SECONDS)))
    if [ "$elapsed" -ge "$next_progress" ]; then
      say "${YELLOW}      Waiting for HTTPS proxy... ${elapsed}s/${timeout_seconds}s${NC}"
      next_progress=$((next_progress + 5))
    fi
    sleep 1
  done

  return 1
}

capture_failure_logs() {
  log "Stack startup failed — capturing container logs"
  run_compose logs >> "$LOG_FILE" 2>&1 || true
}

start_log_tail() {
  stop_log_tails
  (cd "$ROOT_DIR" && "${COMPOSE_CMD[@]}" "${COMPOSE_GLOBAL_ARGS[@]}" logs -f 2>&1) >> "$LOG_FILE" &
  echo $! >> "$TAIL_PID_FILE"
}

print_summary() {
  echo ""
  say "${GREEN}Lumen is running.${NC}"
  echo ""
  echo "  Frontend:   http://localhost:3000"
  echo "  HTTPS:      https://localhost"
  if backend_can_start; then
    echo "  API:        http://localhost:8000"
    echo "  API docs:   http://localhost:8000/docs"
  fi
  echo ""
  echo "  Status:     ./start.sh --status"
  echo "  Logs:       ./start.sh --logs"
  echo "  Clean:      ./start.sh --clean"
  echo "  Stop all:   ./start.sh --down"
  echo "  Rebuild:    ./start.sh --rebuild"
  echo ""
  print_backend_state
  say "${YELLOW}  Log file:   $LOG_FILE${NC}"
}

start_stack() {
  mkdir -p "$LOG_DIR"
  rm -f "$TAIL_PID_FILE"
  trap cleanup_on_interrupt INT TERM

  say "${GREEN}Lumen — Starting services...${NC}"
  echo ""
  log "Starting Lumen (log: $LOG_FILE)"

  bootstrap_project_layout
  configure_compose_flags start
  check_docker
  check_frontend_files
  check_backend_files
  check_ports

  if [ "$FULL_CLEAN" = true ]; then
    say "${YELLOW}Rebuild requested — cleaning existing Lumen services first...${NC}"
    teardown_stack
  elif [ -n "$BUILD_FLAG" ]; then
    say "${YELLOW}Build requested — stopping existing Lumen services first...${NC}"
    teardown_stack
  fi

  say "${YELLOW}Starting Docker Compose app: project-lumen${NC}"
  STARTUP_FAILED=true
  if ! run_compose up -d "${COMPOSE_UP_ARGS[@]}"; then
    capture_failure_logs
    fail "Stack failed to start. Logs saved to $LOG_FILE\nDebug with:\n  cd project-lumen && docker compose logs"
  fi

  if ! wait_for_url "Frontend" "http://127.0.0.1:3000" 60 --silent --show-error --fail; then
    capture_failure_logs
    fail "Frontend did not become ready within 60 seconds. Logs saved to $LOG_FILE"
  fi

  if ! wait_for_proxy 60; then
    capture_failure_logs
    fail "HTTPS proxy did not become ready within 60 seconds. Logs saved to $LOG_FILE"
  fi

  if backend_can_start; then
    if ! wait_for_url "API" "http://127.0.0.1:8000/docs" 60 --silent --show-error --fail; then
      capture_failure_logs
      fail "API did not become ready within 60 seconds. Logs saved to $LOG_FILE"
    fi
  else
    say "${YELLOW}      API skipped until $BACKEND_ENV_FILE is configured.${NC}"
  fi

  STARTUP_FAILED=false
  start_log_tail
  trap - INT TERM
  print_summary
}

show_status() {
  bootstrap_project_layout
  configure_compose_flags manage
  check_docker
  run_compose ps
}

show_logs() {
  bootstrap_project_layout
  configure_compose_flags manage
  check_docker

  if [ -n "$LOGS_SERVICE" ]; then
    run_compose logs -f "$LOGS_SERVICE"
  else
    run_compose logs -f
  fi
}

main() {
  parse_args "$@"

  case "$ACTION" in
    help)
      print_usage
      ;;
    down)
      mkdir -p "$LOG_DIR"
      configure_compose_flags manage
      say "${YELLOW}Stopping all Lumen services...${NC}"
      teardown_stack
      say "${GREEN}All services stopped.${NC}"
      ;;
    clean)
      mkdir -p "$LOG_DIR"
      configure_compose_flags manage
      say "${YELLOW}Cleaning all Lumen services and project data...${NC}"
      teardown_stack
      say "${GREEN}Lumen stack cleaned.${NC}"
      ;;
    status)
      show_status
      ;;
    logs)
      show_logs
      ;;
    doctor)
      doctor
      ;;
    start)
      start_stack
      ;;
    *)
      fail "Unsupported action: $ACTION"
      ;;
  esac
}

main "$@"
