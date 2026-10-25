# Docker Local Test — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build and run ShellFromBrowser in Docker locally, verify the terminal works at http://localhost:8080.

**Architecture:** Single container running the Go binary on port 8080 (HTTP, no TLS, no auth). The `docker-compose.yml` is simplified for local testing, and a minimal `config.yaml` is created.

**Tech Stack:** Docker 29.4.3, Docker Compose v5.1.3, Go 1.26 (golang:1.26-alpine), Alpine 3.19 runtime.

---

## File Structure

| File | Action | Purpose |
|------|--------|---------|
| `config.yaml` | Create | Minimal config for local test (HTTP :8080, no auth, no TLS) |
| `docker-compose.yml` | Modify | Simplify for local test (port 8080, no TLS vars, no certs volume) |
| `Dockerfile` | No change | golang:1.26-alpine confirmed available on Docker Hub |

---

### Task 1: Create `config.yaml` for local testing

**Files:**
- Create: `config.yaml`

- [ ] **Step 1: Create the config file**

```yaml
server:
  addr: ":8080"
  domain: ""

auth:
  enabled: false

shell:
  command: ""
  env:
    - "TERM=xterm-256color"

sessions:
  max_per_user: 10
  idle_timeout: "30m"

recording:
  enabled: false
```

- [ ] **Step 2: Verify the file exists**

Run: `cat config.yaml`
Expected: The YAML content above is displayed.

---

### Task 2: Modify `docker-compose.yml` for local HTTP

**Files:**
- Modify: `docker-compose.yml` (entire file)

- [ ] **Step 1: Replace docker-compose.yml content**

```yaml
services:
  shellfb:
    build: .
    image: valorisa/shellfb:latest
    container_name: shellfb
    ports:
      - "8080:8080"
    environment:
      - SHELLFB_AUTH_ENABLED=false
    volumes:
      - ./config.yaml:/etc/shellfb/config.yaml:ro
    restart: unless-stopped
```

Changes from original:
- Ports: `80:80` + `443:443` → `8080:8080`
- Environment: removed `SHELLFB_DOMAIN`, `SHELLFB_JWT_SECRET`, set `SHELLFB_AUTH_ENABLED=false`
- Volumes: removed `certs` volume and `shellfb-recordings` volume
- Removed top-level `volumes:` section

- [ ] **Step 2: Validate compose syntax**

Run: `docker compose config`
Expected: Parsed YAML output with no errors, showing the service on port 8080.

---

### Task 3: Build the Docker image

**Files:** None (uses existing Dockerfile)

- [ ] **Step 1: Build the image**

Run: `docker compose build`
Expected: Multi-stage build completes successfully:
- Stage 1 (builder): `golang:1.26-alpine` pulls, `go mod download` succeeds, `go build` produces `/bin/shellfb`
- Stage 2 (runtime): `alpine:3.19` pulls, copies binary, sets capabilities

If it fails on `go build`, check the error — likely a missing dependency or compile error, not a Docker issue.

---

### Task 4: Start the container

- [ ] **Step 1: Start in detached mode**

Run: `docker compose up -d`
Expected: Container `shellfb` starts successfully.

- [ ] **Step 2: Verify container is running**

Run: `docker compose ps`
Expected: `shellfb` container with status `Up` and port `0.0.0.0:8080->8080/tcp`.

- [ ] **Step 3: Check container logs for errors**

Run: `docker compose logs --tail=20`
Expected: Startup logs showing the server listening on `:8080`, no panic or fatal errors.

---

### Task 5: Verify the app responds

- [ ] **Step 1: HTTP health check**

Run: `curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/`
Expected: `200` (the embedded frontend is served at root).

- [ ] **Step 2: Check the page content**

Run: `curl -s http://localhost:8080/ | head -20`
Expected: HTML containing references to `xterm.js` or `terminal` — confirming the frontend loads.

- [ ] **Step 3: Open in browser**

Open `http://localhost:8080` in a browser manually. Expected:
- xterm.js terminal UI renders
- A shell prompt appears (bash inside the Alpine container)
- Typing commands (e.g., `ls`, `whoami`) produces output

---

### Task 6: Cleanup (after testing)

- [ ] **Step 1: Stop and remove the container**

Run: `docker compose down`
Expected: Container stopped and removed.

- [ ] **Step 2: Revert modified files (optional)**

Run: `git checkout docker-compose.yml && rm config.yaml`
Expected: Repository back to original state.
