#!/usr/bin/env bash
set -euo pipefail

# ─── Constants ────────────────────────────────────────────────────────
REPO_URL="https://github.com/lukilabs/craft-agents-oss.git"
DEFAULT_PORT=9100
PROJECT_DIR="craft-agent-server"
VERSION="0.1.0"

# ─── Colors ───────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# ─── Helper functions ─────────────────────────────────────────────────
info()  { echo -e "${BLUE}ℹ${NC} $*"; }
ok()    { echo -e "${GREEN}✓${NC} $*"; }
warn()  { echo -e "${YELLOW}⚠${NC} $*"; }
err()   { echo -e "${RED}✗${NC} $*" >&2; }
fatal() { err "$@"; exit 1; }

# ─── Prerequisites ────────────────────────────────────────────────────
check_prerequisites() {
  local missing=0

  info "Checking prerequisites..."

  # Docker
  if command -v docker &>/dev/null; then
    ok "Docker $(docker --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
  else
    err "Docker not found. Install from https://docs.docker.com/get-docker/"
    missing=1
  fi

  # Docker Compose (v2 plugin)
  if docker compose version &>/dev/null; then
    ok "Docker Compose $(docker compose version --short 2>/dev/null || echo 'found')"
  else
    err "Docker Compose not found. Install the Docker Compose plugin."
    missing=1
  fi

  # Git
  if command -v git &>/dev/null; then
    ok "Git $(git --version | awk '{print $3}')"
  else
    err "Git not found. Install from https://git-scm.com/"
    missing=1
  fi

  # OpenSSL
  if command -v openssl &>/dev/null; then
    ok "OpenSSL found"
  else
    err "OpenSSL not found."
    missing=1
  fi

  # Docker daemon running
  if docker info &>/dev/null; then
    ok "Docker daemon running"
  else
    err "Docker daemon not running. Start Docker and try again."
    missing=1
  fi

  if [ "$missing" -ne 0 ]; then
    fatal "Missing prerequisites. Install them and re-run this script."
  fi

  echo ""
}

# ─── Provider Selection ───────────────────────────────────────────────
PROVIDERS=()
ANTHROPIC_KEY=""
OPENAI_KEY=""
GOOGLE_KEY=""
OPENROUTER_KEY=""
OLLAMA_URL=""
CUSTOM_URL=""
CUSTOM_KEY=""

provider_name() {
  case "$1" in
    anthropic)  echo "Anthropic (Claude)" ;;
    openai)     echo "OpenAI" ;;
    google)     echo "Google AI Studio (Gemini)" ;;
    openrouter) echo "OpenRouter" ;;
    ollama)     echo "Ollama (local models)" ;;
    copilot)    echo "GitHub Copilot" ;;
    custom)     echo "Custom endpoint" ;;
  esac
}

select_providers() {
  echo -e "${BOLD}Select LLM provider(s) (comma-separated):${NC}"
  echo ""
  echo "  1) Anthropic (Claude)          - API key"
  echo "  2) OpenAI                      - API key"
  echo "  3) Google AI Studio (Gemini)   - API key"
  echo "  4) OpenRouter                  - API key"
  echo "  5) Ollama (local models)       - no key needed"
  echo "  6) GitHub Copilot              - device code OAuth *"
  echo "  7) Custom endpoint             - URL + optional key"
  echo ""
  echo -e "  ${YELLOW}* Requires one-time browser authorization after setup${NC}"
  echo ""

  read -rp "> " selection

  # Parse comma-separated selection
  IFS=',' read -ra choices <<< "$selection"
  for choice in "${choices[@]}"; do
    choice=$(echo "$choice" | tr -d ' ')
    case "$choice" in
      1) PROVIDERS+=("anthropic") ;;
      2) PROVIDERS+=("openai") ;;
      3) PROVIDERS+=("google") ;;
      4) PROVIDERS+=("openrouter") ;;
      5) PROVIDERS+=("ollama") ;;
      6) PROVIDERS+=("copilot") ;;
      7) PROVIDERS+=("custom") ;;
      *) warn "Unknown selection: $choice (skipping)" ;;
    esac
  done

  if [ ${#PROVIDERS[@]} -eq 0 ]; then
    fatal "No providers selected. At least one provider is required."
  fi

  echo ""
  ok "Selected ${#PROVIDERS[@]} provider(s): ${PROVIDERS[*]}"
  echo ""
}

# ─── Credential Collection ────────────────────────────────────────────
collect_credentials() {
  local count=1
  local total=${#PROVIDERS[@]}

  for provider in "${PROVIDERS[@]}"; do
    echo -e "${BOLD}[$count/$total] $(provider_name "$provider")${NC}"

    case "$provider" in
      anthropic)
        read -rsp "  Enter API key: " ANTHROPIC_KEY
        echo ""
        [ -z "$ANTHROPIC_KEY" ] && fatal "Anthropic API key is required."
        ok "Saved"
        ;;
      openai)
        read -rsp "  Enter API key: " OPENAI_KEY
        echo ""
        [ -z "$OPENAI_KEY" ] && fatal "OpenAI API key is required."
        ok "Saved"
        ;;
      google)
        read -rsp "  Enter API key: " GOOGLE_KEY
        echo ""
        [ -z "$GOOGLE_KEY" ] && fatal "Google AI Studio API key is required."
        ok "Saved"
        ;;
      openrouter)
        read -rsp "  Enter API key: " OPENROUTER_KEY
        echo ""
        [ -z "$OPENROUTER_KEY" ] && fatal "OpenRouter API key is required."
        ok "Saved"
        ;;
      ollama)
        read -rp "  Enter host URL [http://host.docker.internal:11434]: " OLLAMA_URL
        OLLAMA_URL="${OLLAMA_URL:-http://host.docker.internal:11434}"
        ok "Saved (no API key needed)"
        ;;
      copilot)
        warn "GitHub Copilot uses OAuth device flow."
        echo "  After setup, connect the desktop app to this server"
        echo "  and authenticate Copilot through the UI."
        read -rp "  Press Enter to continue..." _
        ok "Will configure post-setup"
        ;;
      custom)
        read -rp "  Enter base URL: " CUSTOM_URL
        [ -z "$CUSTOM_URL" ] && fatal "Custom endpoint URL is required."
        read -rsp "  Enter API key (optional, press Enter to skip): " CUSTOM_KEY
        echo ""
        ok "Saved"
        ;;
    esac

    echo ""
    count=$((count + 1))
  done
}

# ─── Server Configuration ─────────────────────────────────────────────
SERVER_TOKEN=""
SERVER_PORT=""

configure_server() {
  info "Generating server authentication token..."
  SERVER_TOKEN=$(openssl rand -hex 32)
  ok "Token generated"
  echo ""

  read -rp "Server port [${DEFAULT_PORT}]: " SERVER_PORT
  SERVER_PORT="${SERVER_PORT:-$DEFAULT_PORT}"

  # Validate port is a number in range
  if ! [[ "$SERVER_PORT" =~ ^[0-9]+$ ]] || [ "$SERVER_PORT" -lt 1 ] || [ "$SERVER_PORT" -gt 65535 ]; then
    fatal "Invalid port number: $SERVER_PORT"
  fi

  ok "Port: $SERVER_PORT"
  echo ""
}

# ─── File Generation ──────────────────────────────────────────────────
write_env_file() {
  info "Generating .env..."

  cat > .env <<EOF
# ══════════════════════════════════════════════════════════
# Craft Agent Server — auto-generated by setup.sh v${VERSION}
# ══════════════════════════════════════════════════════════

# Server
CRAFT_SERVER_TOKEN=${SERVER_TOKEN}
CRAFT_RPC_HOST=0.0.0.0
CRAFT_RPC_PORT=${SERVER_PORT}
EOF

  # Append provider keys
  {
    echo ""
    echo "# LLM Providers"

    for provider in "${PROVIDERS[@]}"; do
      case "$provider" in
        anthropic)
          echo "ANTHROPIC_API_KEY=${ANTHROPIC_KEY}"
          ;;
        openai)
          echo "OPENAI_API_KEY=${OPENAI_KEY}"
          ;;
        google)
          echo "GOOGLE_API_KEY=${GOOGLE_KEY}"
          ;;
        openrouter)
          echo "OPENROUTER_API_KEY=${OPENROUTER_KEY}"
          ;;
        ollama)
          echo "OLLAMA_BASE_URL=${OLLAMA_URL}"
          ;;
        copilot)
          echo "# GitHub Copilot — authenticate via desktop app after connecting"
          ;;
        custom)
          echo "CUSTOM_BASE_URL=${CUSTOM_URL}"
          [ -n "$CUSTOM_KEY" ] && echo "CUSTOM_API_KEY=${CUSTOM_KEY}"
          ;;
      esac
    done
  } >> .env

  ok ".env generated"
}

write_dockerfile() {
  info "Generating Dockerfile..."

  # Detect architecture for build target
  local host_arch
  host_arch=$(uname -m)
  local build_arch
  case "$host_arch" in
    x86_64)        build_arch="x64" ;;
    aarch64|arm64) build_arch="arm64" ;;
    *) fatal "Unsupported architecture: $host_arch" ;;
  esac

  cat > Dockerfile <<'DOCKERFILE_HEAD'
# ══════════════════════════════════════════════════════════
# Craft Agent Server — Multi-stage Docker build
# Auto-generated by setup.sh
# ══════════════════════════════════════════════════════════

# Stage 1: Build the server distribution
FROM oven/bun:1.3-slim AS builder

RUN apt-get update && apt-get install -y --no-install-recommends git ca-certificates && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /build
COPY craft-agents-oss/ .

RUN bun install --frozen-lockfile
DOCKERFILE_HEAD

  # Write the build command with resolved architecture
  echo "RUN bun run server:build:linux-${build_arch}" >> Dockerfile

  cat >> Dockerfile <<'DOCKERFILE_TAIL'

# Stage 2: Runtime
FROM oven/bun:1.3-slim

WORKDIR /app
COPY --from=builder /build/dist/server/ .

RUN chmod +x bin/craft-server && \
    [ -f vendor/bun/bun ] && chmod +x vendor/bun/bun || true && \
    [ -f resources/bin/uv ] && chmod +x resources/bin/uv || true && \
    for f in resources/bin/*; do [ -f "$f" ] && chmod +x "$f"; done

ENV CRAFT_IS_PACKAGED=true
ENV CRAFT_BUNDLED_ASSETS_ROOT=/app
ENV CRAFT_APP_ROOT=/app
ENV CRAFT_RESOURCES_PATH=/app/resources
ENV CRAFT_UV=/app/resources/bin/uv
ENV CRAFT_SCRIPTS=/app/resources/scripts
ENV CRAFT_RPC_HOST=0.0.0.0
ENV CRAFT_RPC_PORT=9100
ENV PATH="/app/resources/bin:/app/vendor/bun:${PATH}"

EXPOSE 9100

ENTRYPOINT ["/app/bin/craft-server"]
DOCKERFILE_TAIL

  ok "Dockerfile generated (linux-${build_arch})"
}

write_compose_file() {
  info "Generating docker-compose.yml..."

  cat > docker-compose.yml <<'COMPOSE'
version: "3.8"
services:
  craft-server:
    build:
      context: .
      dockerfile: Dockerfile
    ports:
      - "${CRAFT_RPC_PORT:-9100}:9100"
    env_file: .env
    volumes:
      - craft-data:/root/.craft-agent
    restart: unless-stopped

volumes:
  craft-data:
COMPOSE

  ok "docker-compose.yml generated"
}

write_dockerignore() {
  info "Generating .dockerignore..."

  cat > .dockerignore <<'IGNORE'
craft-agents-oss/.git
craft-agents-oss/node_modules
craft-agents-oss/dist
craft-agents-oss/.env
.env
.git
IGNORE

  ok ".dockerignore generated"
}

# ─── Clone, Build & Start ─────────────────────────────────────────────
clone_repo() {
  if [ -d "craft-agents-oss" ]; then
    info "craft-agents-oss already cloned, pulling latest..."
    (cd craft-agents-oss && git pull --ff-only)
  else
    info "Cloning craft-agents-oss (shallow)..."
    git clone --depth 1 "$REPO_URL"
  fi
  ok "Repository ready"
  echo ""
}

build_image() {
  info "Building Docker image (this may take a few minutes)..."
  echo ""
  docker compose build
  echo ""
  ok "Docker image built"
  echo ""
}

start_server() {
  info "Starting Craft Agent Server..."
  docker compose up -d
  ok "Server started"
  echo ""
}

# ─── Connection Info ───────────────────────────────────────────────────
print_connection_info() {
  # Detect public/local IP
  local ip
  ip=$(hostname -I 2>/dev/null | awk '{print $1}' || hostname -i 2>/dev/null || echo "127.0.0.1")

  echo ""
  echo -e "${BOLD}═══════════════════════════════════════════════════${NC}"
  echo -e "${GREEN}  ✓ Craft Agent Server is running!${NC}"
  echo ""
  echo "  CRAFT_SERVER_URL=ws://${ip}:${SERVER_PORT}"
  echo "  CRAFT_SERVER_TOKEN=${SERVER_TOKEN}"
  echo ""
  echo "  Providers configured:"
  for provider in "${PROVIDERS[@]}"; do
    local name
    name=$(provider_name "$provider")
    if [ "$provider" = "copilot" ]; then
      echo -e "    ${YELLOW}⏳ ${name} (authenticate via desktop app)${NC}"
    else
      echo -e "    ${GREEN}✓${NC} ${name}"
    fi
  done
  echo ""
  echo "  Day-2 commands (run from $(pwd)):"
  echo "    docker compose up -d       Start"
  echo "    docker compose down         Stop"
  echo "    docker compose ps           Status"
  echo "    docker compose logs -f      Logs"
  echo "    docker compose build        Rebuild after update"
  echo -e "${BOLD}═══════════════════════════════════════════════════${NC}"
  echo ""
}

# ─── Main ──────────────────────────────────────────────────────────────
main() {
  echo ""
  echo -e "${BOLD}═══════════════════════════════════════════════════${NC}"
  echo -e "${BOLD}  Craft Agent Server — Docker Setup v${VERSION}${NC}"
  echo -e "${BOLD}═══════════════════════════════════════════════════${NC}"
  echo ""

  check_prerequisites
  select_providers
  collect_credentials
  configure_server

  # Create and enter project directory
  mkdir -p "$PROJECT_DIR"
  cd "$PROJECT_DIR"

  write_env_file
  write_dockerfile
  write_compose_file
  write_dockerignore
  clone_repo
  build_image
  start_server
  print_connection_info
}

main "$@"
