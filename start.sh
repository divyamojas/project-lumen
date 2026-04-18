#!/bin/bash

# Lumen — Start All Services
# Usage:
#   ./start.sh           → start everything
#   ./start.sh --build   → rebuild images first
#   ./start.sh --down    → stop everything

# Do NOT use set -e — we handle errors explicitly with messages

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FRONTEND_DIR="$ROOT_DIR/project-lumen-light"
BACKEND_DIR="$ROOT_DIR/project-lumen-source"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

BUILD_FLAG=""
TAKE_DOWN=false

for arg in "$@"; do
  case $arg in
    --build) BUILD_FLAG="--build" ;;
    --down)  TAKE_DOWN=true ;;
  esac
done

# ── Helper ─────────────────────────────────────────────────────
fail() {
  echo -e "${RED}ERROR: $1${NC}"
  exit 1
}

# ── Tear Down ──────────────────────────────────────────────────
if [ "$TAKE_DOWN" = true ]; then
  echo -e "${YELLOW}Stopping all Lumen services...${NC}"
  if [ -d "$BACKEND_DIR" ]; then
    echo -e "${YELLOW}→ Stopping API...${NC}"
    cd "$ROOT_DIR" && docker compose down 2>/dev/null || true
  fi
  if [ -d "$FRONTEND_DIR" ]; then
    echo -e "${YELLOW}→ Stopping frontend...${NC}"
    cd "$FRONTEND_DIR" && docker compose down 2>/dev/null || true
  fi
  echo -e "${GREEN}All services stopped.${NC}"
  exit 0
fi

# ── Pre-flight Checks ──────────────────────────────────────────
echo -e "${GREEN}Lumen — Starting services...${NC}"
echo ""

# Check Docker is running
if ! docker info > /dev/null 2>&1; then
  fail "Docker is not running. Start Docker Desktop and try again."
fi

# Check docker compose is available (not docker-compose)
if ! docker compose version > /dev/null 2>&1; then
  fail "docker compose not available. Update Docker Desktop to a version that includes the compose plugin."
fi

# Check frontend repo exists
if [ ! -d "$FRONTEND_DIR" ]; then
  fail "Frontend not found at $FRONTEND_DIR\nClone it first:\n  git clone https://github.com/divyamojas/project-lumen-light"
fi

# Check for port conflicts
for PORT in 3000 8000 80 443; do
  if lsof -iTCP:$PORT -sTCP:LISTEN > /dev/null 2>&1; then
    fail "Port $PORT is already in use. Stop the conflicting process and try again.\n  Find it with: lsof -iTCP:$PORT -sTCP:LISTEN"
  fi
done

# Check backend .env exists if backend folder exists
if [ -d "$BACKEND_DIR" ] && [ ! -f "$BACKEND_DIR/.env" ]; then
  fail "Backend .env file not found at $BACKEND_DIR/.env\nCopy the example and fill in your values:\n  cp $BACKEND_DIR/.env.example $BACKEND_DIR/.env"
fi

# ── Step 1: Start Frontend ──────────────────────────────────────
echo -e "${YELLOW}[1/2] Starting frontend...${NC}"
cd "$FRONTEND_DIR"
if ! docker compose up -d $BUILD_FLAG; then
  fail "Frontend failed to start.\nDebug with:\n  cd project-lumen-light && docker compose logs"
fi

# Wait for lumen network
echo -e "${YELLOW}      Waiting for lumen network...${NC}"
NETWORK_READY=false
for i in {1..15}; do
  if docker network inspect lumen > /dev/null 2>&1; then
    NETWORK_READY=true
    break
  fi
  sleep 1
done

if [ "$NETWORK_READY" = false ]; then
  echo -e "${RED}Timed out waiting for lumen network.${NC}"
  echo -e "${RED}Check what went wrong:${NC}"
  echo -e "${RED}  cd project-lumen-light && docker compose logs${NC}"
  echo -e "${YELLOW}Cleaning up frontend...${NC}"
  cd "$FRONTEND_DIR" && docker compose down 2>/dev/null || true
  exit 1
fi
echo -e "${GREEN}      Frontend ready.${NC}"

# ── Step 2: Start API ───────────────────────────────────────────
if [ -d "$BACKEND_DIR" ]; then
  echo -e "${YELLOW}[2/2] Starting API...${NC}"
  cd "$ROOT_DIR"
  if ! docker compose up -d $BUILD_FLAG; then
    echo -e "${RED}API failed to start.${NC}"
    echo -e "${RED}Debug with:${NC}"
    echo -e "${RED}  cd project-lumen && docker compose logs${NC}"
    echo -e "${YELLOW}Frontend is still running at http://localhost:3000${NC}"
    exit 1
  fi
  echo -e "${GREEN}      API ready.${NC}"
else
  echo -e "${YELLOW}[2/2] project-lumen-source not found — skipping API.${NC}"
  echo -e "${YELLOW}      Clone when ready:${NC}"
  echo -e "${YELLOW}      git clone https://github.com/divyamojas/project-lumen-source${NC}"
fi

# ── Summary ────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}Lumen is running.${NC}"
echo ""
echo "  Frontend:   http://localhost:3000"
echo "  HTTPS:      https://localhost"
if [ -d "$BACKEND_DIR" ]; then
  echo "  API:        http://localhost:8000"
  echo "  API docs:   http://localhost:8000/docs"
fi
echo ""
echo "  Stop all:   ./start.sh --down"
echo "  Rebuild:    ./start.sh --build"
