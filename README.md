# Craft Docker Setup

One-command setup for [Craft Agents](https://github.com/lukilabs/craft-agents-oss) headless server using Docker.

## Quick Start

```bash
curl -fsSL https://raw.githubusercontent.com/<your-repo>/main/setup.sh -o setup.sh
chmod +x setup.sh
./setup.sh
```

Or clone and run:

```bash
git clone https://github.com/<your-repo>/craft-docker-setup.git
cd craft-docker-setup
./setup.sh
```

## Prerequisites

- **Docker** (with Docker Compose v2 plugin)
- **Git**
- **OpenSSL**

That's it. No Bun, Node.js, or other runtimes needed — everything builds inside Docker.

## What It Does

1. **Checks prerequisites** — Docker, Docker Compose, Git, OpenSSL
2. **Runs an interactive wizard** — select LLM providers, enter API keys
3. **Generates Docker files** — multi-stage Dockerfile, docker-compose.yml, .env
4. **Clones craft-agents-oss** — shallow clone for faster setup
5. **Builds & starts** — `docker compose build` + `docker compose up -d`
6. **Prints connection info** — server URL and token ready to use

## Supported Providers

| # | Provider | Auth Type | Notes |
|---|----------|-----------|-------|
| 1 | Anthropic (Claude) | API key | |
| 2 | OpenAI | API key | |
| 3 | Google AI Studio (Gemini) | API key | |
| 4 | OpenRouter | API key | Multi-model gateway |
| 5 | Ollama | URL (no key) | Local models via `host.docker.internal` |
| 6 | GitHub Copilot | OAuth device flow | Authenticate via desktop app post-setup |
| 7 | Custom endpoint | URL + optional key | Any compatible API |

You can select **multiple providers** (comma-separated) during setup.

## Generated Files

After setup, your `craft-agent-server/` directory contains:

```
craft-agent-server/
├── .env                    # Secrets & provider config
├── .dockerignore           # Build context exclusions
├── docker-compose.yml      # Docker Compose service
├── Dockerfile              # Multi-stage build
└── craft-agents-oss/       # Cloned repo (build source)
```

## Day-2 Commands

After setup, use standard Docker Compose commands from the `craft-agent-server/` directory:

```bash
docker compose up -d       # Start
docker compose down         # Stop
docker compose ps           # Status
docker compose logs -f      # Logs
docker compose build        # Rebuild (e.g., after updating craft-agents-oss)
```

## Connecting the Desktop App

Launch the Craft Agents desktop app in thin-client mode:

```bash
CRAFT_SERVER_URL=ws://<server-ip>:9100 CRAFT_SERVER_TOKEN=<token> craft-agents
```

Or on macOS:

```bash
CRAFT_SERVER_URL=ws://<server-ip>:9100 \
CRAFT_SERVER_TOKEN=<token> \
open -a "Craft Agents"
```

The desktop app renders the UI while all processing runs on the remote server.

## Updating

To update to the latest craft-agents-oss version:

```bash
cd craft-agent-server
cd craft-agents-oss && git pull && cd ..
docker compose build
docker compose up -d
```

## Architecture

The setup uses a **multi-stage Docker build**:

1. **Build stage** (`oven/bun:1.3-slim`) — installs dependencies, runs `bun run server:build:linux-{arch}`
2. **Runtime stage** (`oven/bun:1.3-slim`) — copies only the built server distribution (~200MB)

Host architecture (x64/arm64) is auto-detected and the correct Linux binary is built.

## License

MIT
