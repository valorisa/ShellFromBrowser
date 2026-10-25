# ShellFromBrowser

[![CI](https://github.com/valorisa/ShellFromBrowser/actions/workflows/ci.yml/badge.svg)](https://github.com/valorisa/ShellFromBrowser/actions/workflows/ci.yml)
[![Go Version](https://img.shields.io/github/go-mod/go-version/valorisa/ShellFromBrowser)](https://go.dev/)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-linux%20%7C%20macos%20%7C%20windows-lightgrey)](https://github.com/valorisa/ShellFromBrowser/releases)
[![Docker](https://img.shields.io/badge/docker-ready-2496ED?logo=docker&logoColor=white)](Dockerfile)

> 🇫🇷 **[Lire en français](README.fr.md)**

**A network-traversing, web-based terminal emulator.** ShellFromBrowser works everywhere a browser can open a website — airports, train stations, corporate networks, anywhere. It uses standard HTTPS on port 443: no firewall can tell it apart from a regular web visit.

A modern, cross-platform terminal emulator written in Go. Spiritual successor to [ShellInBox](https://code.google.com/archive/p/shellinabox/) — rebuilt from scratch with WebSocket, xterm.js, SSH client support, multi-sessions, file transfer, and session recording.

---

## Features

| Feature | Description |
|---------|-------------|
| **Browser-based terminal** | Full xterm.js emulation — 256 colors, Unicode, mouse support, clipboard |
| **Multi-session tabs** | Open multiple terminal sessions in one browser window, switch between them |
| **SSH client** | Connect to remote hosts directly from the browser (`user@host:port`) |
| **Authentication** | JWT-based auth with bcrypt password hashing, configurable per-user |
| **TLS/HTTPS** | Built-in TLS support — just provide cert and key paths |
| **File transfer** | Upload/download files through the web interface with path traversal protection |
| **Session recording** | Record and replay terminal sessions in asciicast v2 format (asciinema-compatible) |
| **Cross-platform** | Runs natively on Linux, macOS, and Windows (ConPTY) |
| **Single binary** | Zero runtime dependencies — frontend, assets, everything embedded via `go:embed` |
| **Docker ready** | Multi-stage Dockerfile + docker-compose included |

---

## Quick Start

### Prerequisites

- [Go 1.27+](https://go.dev/dl/) installed (required for Options 1, 2, and 4)
- [Docker](https://docs.docker.com/get-docker/) installed (required for Option 3 only)

### Option 1: Quick test (no install needed)

The fastest way to try ShellFromBrowser. Works on Windows, macOS, and Linux — Go handles the cross-platform differences automatically.

```bash
git clone https://github.com/valorisa/ShellFromBrowser.git
cd ShellFromBrowser

# Launch directly without installing (compiles and runs in one step)
go run ./cmd/shellfb
```

Then open http://localhost:4200 in your browser. You should see an interactive terminal (xterm.js).

> This does **not** install anything on your system. It compiles a temporary binary and runs it. Stop it with `Ctrl+C`.

### Option 2: Install globally

Installs the `shellfb` binary into your `$GOPATH/bin` (or `%GOPATH%\bin` on Windows), making it available system-wide.

```bash
go install github.com/valorisa/ShellFromBrowser/cmd/shellfb@latest

# Run with defaults (no auth, port 4200)
shellfb

# Run with custom address
shellfb --addr :3000

# Run with configuration file
shellfb --config config.yaml

# Display version
shellfb --version
```

Then open http://localhost:4200 (or your custom port) in your browser. Stop it with `Ctrl+C`.

### Option 3: Docker (deployment)

The default `docker-compose.yml` exposes ports 80/443 with auto-TLS — designed for deployment on restricted networks (airports, train stations, corporate firewalls) where only standard HTTPS traffic passes through.

```bash
git clone https://github.com/valorisa/ShellFromBrowser.git
cd ShellFromBrowser

# Create your configuration
cp config.example.yaml config.yaml
# Edit config.yaml: set your domain, auth, etc.

docker compose up -d
```

Open `https://your-domain.com` — the terminal is ready. To stop: `docker compose down`.

> **Local testing with Docker?** You can run without TLS:
> ```bash
> docker build -t shellfb .
> docker run --rm --name shellfb-test -p 4200:4200 shellfb
> ```
> Then open http://localhost:4200. Stop it with `Ctrl+C`, or from another terminal: `docker stop shellfb-test`.

### Option 4: Build from source (Makefile)

Compiles the binary into `./bin/shellfb`. Useful for development or packaging.

```bash
git clone https://github.com/valorisa/ShellFromBrowser.git
cd ShellFromBrowser

# Build the binary
make build

# Run it
./bin/shellfb

# Run the test suite
make test
```

Then open http://localhost:4200 in your browser. Stop it with `Ctrl+C`.

---

## Configuration

Copy `config.example.yaml` to `config.yaml` and customize:

```yaml
server:
  addr: ":4200"
  tls:
    enabled: true
    cert: "/path/to/cert.pem"
    key: "/path/to/key.pem"

auth:
  enabled: true
  jwt_secret: "generate-a-random-string-here"
  users:
    - username: admin
      password_hash: "$2a$10$..."
    - username: developer
      password_hash: "$2a$10$..."

shell:
  # Leave empty for system default (SHELL on Unix, COMSPEC on Windows)
  command: ""
  env:
    - "TERM=xterm-256color"

sessions:
  max_per_user: 10
  idle_timeout: "30m"

ssh:
  enabled: true
  known_hosts: "~/.ssh/known_hosts"

recording:
  enabled: true
  dir: "./recordings"
```

### Generate a password hash

```bash
shellfb hash-password
# Enter password: ********
# $2a$10$xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

Copy the output into your `config.yaml` under `password_hash`.

### CLI options

| Flag | Default | Description |
|------|---------|-------------|
| `--addr` | `:4200` | Listen address (overrides config file) |
| `--config` | none | Path to YAML configuration file |
| `--version` | — | Print version and exit |

Subcommands:

| Command | Description |
|---------|-------------|
| `hash-password` | Generate a bcrypt hash for use in config |

---

## SSH Client Usage

Connect to remote hosts directly from the browser by opening a WebSocket connection to `/ws/ssh`:

```
ws://localhost:4200/ws/ssh?target=user@host.com:22&password=secret&token=JWT_TOKEN
```

Parameters:
- `target` (required): SSH target in format `user@host:port` (port defaults to 22)
- `password`: Password authentication
- `key`: Path to private key file (server-side)
- `token`: JWT authentication token

---

## API Endpoints

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| POST | `/api/login` | No | Authenticate and receive JWT token |
| GET | `/api/sessions` | Yes | List active terminal sessions |
| DELETE | `/api/sessions?id=X` | Yes | Destroy a specific session |
| POST | `/api/upload` | Yes | Upload a file (multipart) |
| GET | `/api/download?file=X` | Yes | Download a file |
| GET | `/api/recordings` | Yes | List recorded sessions |
| GET | `/api/recordings/get?id=X` | Yes | Get recording data (asciicast v2) |
| WS | `/ws` | Yes | Terminal WebSocket (local shell) |
| WS | `/ws/ssh` | Yes | SSH WebSocket (remote host) |

---

## Security

- **Authentication**: JWT tokens with configurable expiry (24h default)
- **Rate limiting**: Login endpoint limited to 5 attempts per minute per IP
- **Security headers**: CSP, X-Frame-Options (DENY), X-Content-Type-Options, Referrer-Policy
- **Path traversal protection**: All file operations validated against base directory
- **No eval()**: No inline scripts, no dynamic code execution in frontend
- **TLS**: Built-in HTTPS support — no reverse proxy required
- **WebSocket auth**: All WebSocket connections require valid JWT token when auth is enabled

---

## Project Structure

```
ShellFromBrowser/
├── cmd/shellfb/          # Entry point, CLI
├── internal/
│   ├── auth/             # JWT + bcrypt authentication
│   ├── config/           # YAML configuration
│   ├── recording/        # Asciicast v2 session recording
│   ├── server/           # HTTP server, WebSocket, middleware
│   ├── ssh/              # SSH client wrapper
│   ├── terminal/         # PTY session management (Unix + Windows)
│   └── transfer/         # File upload/download
├── web/
│   └── static/           # Embedded frontend (xterm.js, CSS, JS)
├── config.example.yaml   # Example configuration
├── Dockerfile            # Multi-stage Docker build
├── docker-compose.yml    # Ready-to-use deployment
└── Makefile              # Build automation
```

---

## License

[MIT](LICENSE) — Copyright (c) 2026 valorisa
