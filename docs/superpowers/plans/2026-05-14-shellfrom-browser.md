# ShellFromBrowser Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a modern, cross-platform web-based terminal emulator in Go that replaces the obsolete ShellInBox — with SSH client, multi-sessions, file transfer, session recording, and Docker support.

**Architecture:** Go HTTP server with WebSocket upgrade for bidirectional terminal I/O. Frontend uses xterm.js for accurate terminal emulation. Sessions are multiplexed server-side with reconnection support. Authentication via JWT tokens with configurable backends (local users, PAM on Linux). SSH client mode allows connecting to remote hosts through the browser.

**Tech Stack:**
- Backend: Go 1.22+
- WebSocket: `github.com/gorilla/websocket`
- PTY: `github.com/creack/pty` (Unix) + ConPTY wrapper (Windows)
- SSH: `golang.org/x/crypto/ssh`
- Frontend: xterm.js 5.x + xterm-addon-fit + xterm-addon-web-links
- Config: `gopkg.in/yaml.v3`
- Auth: JWT (`github.com/golang-jwt/jwt/v5`) + bcrypt
- Build: Go modules, embedded frontend via `embed`

---

## File Structure

```
ShellFromBrowser/
├── cmd/
│   └── shellfb/
│       └── main.go                  # Entry point, CLI flags, server startup
├── internal/
│   ├── config/
│   │   ├── config.go               # Config struct + YAML loading
│   │   └── config_test.go
│   ├── auth/
│   │   ├── auth.go                  # Auth interface + JWT middleware
│   │   ├── local.go                 # Local user/password backend
│   │   ├── pam.go                   # PAM backend (Linux only, build tag)
│   │   └── auth_test.go
│   ├── terminal/
│   │   ├── session.go              # Session lifecycle (create, attach, detach, destroy)
│   │   ├── pty_unix.go             # PTY spawning for Unix (build tag)
│   │   ├── pty_windows.go          # ConPTY for Windows (build tag)
│   │   ├── manager.go             # Session manager (multi-session registry)
│   │   └── session_test.go
│   ├── ssh/
│   │   ├── client.go               # SSH client wrapper
│   │   ├── known_hosts.go          # Known hosts management
│   │   └── client_test.go
│   ├── transfer/
│   │   ├── upload.go               # File upload handler
│   │   ├── download.go             # File download handler
│   │   └── transfer_test.go
│   ├── recording/
│   │   ├── recorder.go             # Session recording (asciicast v2 format)
│   │   ├── player.go               # Playback handler
│   │   └── recorder_test.go
│   └── server/
│       ├── server.go               # HTTP server, routes, WebSocket upgrade
│       ├── websocket.go            # WebSocket handler + message protocol
│       └── server_test.go
├── web/
│   ├── static/
│   │   ├── index.html              # Main SPA page
│   │   ├── css/
│   │   │   └── app.css             # Custom styles
│   │   └── js/
│   │       ├── terminal.js         # xterm.js initialization + WebSocket bridge
│   │       ├── sessions.js         # Multi-tab/session UI logic
│   │       └── transfer.js         # File upload/download UI
│   └── embed.go                    # go:embed directive for static files
├── config.example.yaml             # Example configuration
├── Dockerfile                      # Multi-stage build
├── docker-compose.yml              # Ready-to-use compose file
├── Makefile                        # Build, test, lint targets
├── go.mod
├── go.sum
├── README.md
└── LICENSE
```

---

## Phase 1: Project Scaffold + Basic Terminal

### Task 1: Initialize Go module and project structure

**Files:**
- Create: `go.mod`
- Create: `cmd/shellfb/main.go`
- Create: `Makefile`

- [ ] **Step 1: Create Go module**

```bash
cd ShellFromBrowser
go mod init github.com/valorisa/ShellFromBrowser
```

- [ ] **Step 2: Create entry point**

Create `cmd/shellfb/main.go`:
```go
package main

import (
	"flag"
	"fmt"
	"log"
	"os"
	"os/signal"
	"syscall"
)

var (
	version = "dev"
	commit  = "none"
)

func main() {
	addr := flag.String("addr", ":8080", "listen address (host:port)")
	configPath := flag.String("config", "", "path to config file")
	showVersion := flag.Bool("version", false, "print version and exit")
	flag.Parse()

	if *showVersion {
		fmt.Printf("ShellFromBrowser %s (%s)\n", version, commit)
		os.Exit(0)
	}

	_ = configPath // used in Phase 4
	log.Printf("ShellFromBrowser %s starting on %s", version, *addr)

	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit
	log.Println("shutting down")
}
```

- [ ] **Step 3: Create Makefile**

Create `Makefile`:
```makefile
BINARY=shellfb
VERSION=$(shell git describe --tags --always --dirty 2>/dev/null || echo "dev")
COMMIT=$(shell git rev-parse --short HEAD 2>/dev/null || echo "none")
LDFLAGS=-ldflags "-X main.version=$(VERSION) -X main.commit=$(COMMIT)"

.PHONY: build test run clean

build:
	go build $(LDFLAGS) -o bin/$(BINARY) ./cmd/shellfb

test:
	go test ./... -v -race

run: build
	./bin/$(BINARY)

clean:
	rm -rf bin/
```

- [ ] **Step 4: Verify build**

```bash
cd ShellFromBrowser
go build ./cmd/shellfb
```

Expected: builds without error.

- [ ] **Step 5: Commit**

```bash
git init
git add go.mod cmd/shellfb/main.go Makefile
git commit -m "feat: initialize project scaffold with entry point and Makefile"
```

---

### Task 2: WebSocket server with echo

**Files:**
- Modify: `cmd/shellfb/main.go`
- Create: `internal/server/server.go`
- Create: `internal/server/websocket.go`
- Create: `internal/server/server_test.go`

- [ ] **Step 1: Write the failing test**

Create `internal/server/server_test.go`:
```go
package server_test

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/gorilla/websocket"
	"github.com/valorisa/ShellFromBrowser/internal/server"
)

func TestWebSocketEcho(t *testing.T) {
	srv := server.New(":0")
	ts := httptest.NewServer(srv.Handler())
	defer ts.Close()

	wsURL := "ws" + strings.TrimPrefix(ts.URL, "http") + "/ws"
	ws, _, err := websocket.DefaultDialer.Dial(wsURL, nil)
	if err != nil {
		t.Fatalf("dial: %v", err)
	}
	defer ws.Close()

	msg := []byte("hello")
	err = ws.WriteMessage(websocket.TextMessage, msg)
	if err != nil {
		t.Fatalf("write: %v", err)
	}

	_, got, err := ws.ReadMessage()
	if err != nil {
		t.Fatalf("read: %v", err)
	}
	if string(got) != string(msg) {
		t.Errorf("got %q, want %q", got, msg)
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
go test ./internal/server/ -v -run TestWebSocketEcho
```

Expected: FAIL — package doesn't exist yet.

- [ ] **Step 3: Add gorilla/websocket dependency**

```bash
go get github.com/gorilla/websocket
```

- [ ] **Step 4: Implement server**

Create `internal/server/server.go`:
```go
package server

import (
	"net/http"
)

type Server struct {
	addr string
	mux  *http.ServeMux
}

func New(addr string) *Server {
	s := &Server{addr: addr, mux: http.NewServeMux()}
	s.mux.HandleFunc("/ws", s.handleWebSocket)
	return s
}

func (s *Server) Handler() http.Handler {
	return s.mux
}

func (s *Server) ListenAndServe() error {
	return http.ListenAndServe(s.addr, s.mux)
}
```

Create `internal/server/websocket.go`:
```go
package server

import (
	"log"
	"net/http"

	"github.com/gorilla/websocket"
)

var upgrader = websocket.Upgrader{
	CheckOrigin: func(r *http.Request) bool { return true },
}

func (s *Server) handleWebSocket(w http.ResponseWriter, r *http.Request) {
	conn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		log.Printf("websocket upgrade: %v", err)
		return
	}
	defer conn.Close()

	for {
		msgType, msg, err := conn.ReadMessage()
		if err != nil {
			break
		}
		if err := conn.WriteMessage(msgType, msg); err != nil {
			break
		}
	}
}
```

- [ ] **Step 5: Run test to verify it passes**

```bash
go test ./internal/server/ -v -run TestWebSocketEcho
```

Expected: PASS

- [ ] **Step 6: Wire server into main.go**

Replace `cmd/shellfb/main.go`:
```go
package main

import (
	"flag"
	"fmt"
	"log"
	"os"
	"os/signal"
	"syscall"

	"github.com/valorisa/ShellFromBrowser/internal/server"
)

var (
	version = "dev"
	commit  = "none"
)

func main() {
	addr := flag.String("addr", ":8080", "listen address (host:port)")
	configPath := flag.String("config", "", "path to config file")
	showVersion := flag.Bool("version", false, "print version and exit")
	flag.Parse()

	if *showVersion {
		fmt.Printf("ShellFromBrowser %s (%s)\n", version, commit)
		os.Exit(0)
	}

	_ = configPath

	srv := server.New(*addr)
	log.Printf("ShellFromBrowser %s starting on %s", version, *addr)

	go func() {
		if err := srv.ListenAndServe(); err != nil {
			log.Fatalf("server: %v", err)
		}
	}()

	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit
	log.Println("shutting down")
}
```

- [ ] **Step 7: Commit**

```bash
git add internal/server/ cmd/shellfb/main.go go.mod go.sum
git commit -m "feat: add WebSocket server with echo handler"
```

---

### Task 3: xterm.js frontend with WebSocket bridge

**Files:**
- Create: `web/static/index.html`
- Create: `web/static/js/terminal.js`
- Create: `web/static/css/app.css`
- Create: `web/embed.go`
- Modify: `internal/server/server.go`

- [ ] **Step 1: Create frontend HTML**

Create `web/static/index.html`:
```html
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>ShellFromBrowser</title>
    <link rel="stylesheet" href="/static/css/xterm.css">
    <link rel="stylesheet" href="/static/css/app.css">
</head>
<body>
    <div id="terminal-container">
        <div id="terminal"></div>
    </div>
    <script src="/static/js/xterm.js"></script>
    <script src="/static/js/xterm-addon-fit.js"></script>
    <script src="/static/js/xterm-addon-web-links.js"></script>
    <script src="/static/js/terminal.js"></script>
</body>
</html>
```

- [ ] **Step 2: Create terminal.js WebSocket bridge**

Create `web/static/js/terminal.js`:
```javascript
(function () {
    "use strict";

    const term = new Terminal({
        cursorBlink: true,
        fontSize: 14,
        fontFamily: "'JetBrains Mono', 'Fira Code', monospace",
        theme: {
            background: "#1e1e2e",
            foreground: "#cdd6f4",
            cursor: "#f5e0dc",
        },
    });

    const fitAddon = new FitAddon.FitAddon();
    const webLinksAddon = new WebLinksAddon.WebLinksAddon();

    term.loadAddon(fitAddon);
    term.loadAddon(webLinksAddon);
    term.open(document.getElementById("terminal"));
    fitAddon.fit();

    window.addEventListener("resize", () => fitAddon.fit());

    const protocol = window.location.protocol === "https:" ? "wss:" : "ws:";
    const wsUrl = `${protocol}//${window.location.host}/ws`;
    let ws = null;

    function connect() {
        ws = new WebSocket(wsUrl);
        ws.binaryType = "arraybuffer";

        ws.onopen = function () {
            term.writeln("\x1b[32mConnected to ShellFromBrowser\x1b[0m");
            const dims = { type: "resize", cols: term.cols, rows: term.rows };
            ws.send(JSON.stringify(dims));
        };

        ws.onmessage = function (event) {
            if (event.data instanceof ArrayBuffer) {
                term.write(new Uint8Array(event.data));
            } else {
                term.write(event.data);
            }
        };

        ws.onclose = function () {
            term.writeln("\r\n\x1b[31mDisconnected\x1b[0m");
        };

        ws.onerror = function () {
            term.writeln("\r\n\x1b[31mConnection error\x1b[0m");
        };
    }

    term.onData(function (data) {
        if (ws && ws.readyState === WebSocket.OPEN) {
            ws.send(data);
        }
    });

    term.onResize(function (size) {
        if (ws && ws.readyState === WebSocket.OPEN) {
            const dims = { type: "resize", cols: size.cols, rows: size.rows };
            ws.send(JSON.stringify(dims));
        }
    });

    connect();
})();
```

- [ ] **Step 3: Create CSS**

Create `web/static/css/app.css`:
```css
* {
    margin: 0;
    padding: 0;
    box-sizing: border-box;
}

html, body {
    height: 100%;
    background: #1e1e2e;
    overflow: hidden;
}

#terminal-container {
    height: 100%;
    padding: 4px;
}

#terminal {
    height: 100%;
}
```

- [ ] **Step 4: Create embed.go for static files**

Create `web/embed.go`:
```go
package web

import "embed"

//go:embed static
var StaticFiles embed.FS
```

- [ ] **Step 5: Download xterm.js assets**

```bash
cd ShellFromBrowser/web/static
mkdir -p js css
curl -sL https://cdn.jsdelivr.net/npm/xterm@5.3.0/lib/xterm.js -o js/xterm.js
curl -sL https://cdn.jsdelivr.net/npm/xterm@5.3.0/css/xterm.css -o css/xterm.css
curl -sL https://cdn.jsdelivr.net/npm/@xterm/addon-fit@0.10.0/lib/addon-fit.js -o js/xterm-addon-fit.js
curl -sL https://cdn.jsdelivr.net/npm/@xterm/addon-web-links@0.11.0/lib/addon-web-links.js -o js/xterm-addon-web-links.js
```

- [ ] **Step 6: Serve static files from server**

Modify `internal/server/server.go`:
```go
package server

import (
	"io/fs"
	"net/http"

	"github.com/valorisa/ShellFromBrowser/web"
)

type Server struct {
	addr string
	mux  *http.ServeMux
}

func New(addr string) *Server {
	s := &Server{addr: addr, mux: http.NewServeMux()}
	s.mux.HandleFunc("/ws", s.handleWebSocket)

	staticFS, _ := fs.Sub(web.StaticFiles, "static")
	s.mux.Handle("/static/", http.StripPrefix("/static/", http.FileServer(http.FS(staticFS))))
	s.mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/" {
			http.NotFound(w, r)
			return
		}
		data, _ := web.StaticFiles.ReadFile("static/index.html")
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		w.Write(data)
	})

	return s
}

func (s *Server) Handler() http.Handler {
	return s.mux
}

func (s *Server) ListenAndServe() error {
	return http.ListenAndServe(s.addr, s.mux)
}
```

- [ ] **Step 7: Build and test manually in browser**

```bash
cd ShellFromBrowser
go build -o bin/shellfb.exe ./cmd/shellfb
./bin/shellfb.exe
```

Open `http://localhost:8080` — should see xterm.js terminal with "Connected" message. Typing echoes back (echo mode from Task 2).

- [ ] **Step 8: Commit**

```bash
git add web/ internal/server/server.go
git commit -m "feat: add xterm.js frontend with WebSocket bridge and embedded static files"
```

---

### Task 4: PTY spawning (cross-platform)

**Files:**
- Create: `internal/terminal/session.go`
- Create: `internal/terminal/pty_unix.go`
- Create: `internal/terminal/pty_windows.go`
- Create: `internal/terminal/session_test.go`
- Modify: `internal/server/websocket.go`

- [ ] **Step 1: Write the failing test**

Create `internal/terminal/session_test.go`:
```go
package terminal_test

import (
	"bytes"
	"testing"
	"time"

	"github.com/valorisa/ShellFromBrowser/internal/terminal"
)

func TestSessionSpawnAndWrite(t *testing.T) {
	sess, err := terminal.NewSession(80, 24)
	if err != nil {
		t.Fatalf("NewSession: %v", err)
	}
	defer sess.Close()

	// Write a command
	_, err = sess.Write([]byte("echo hello\n"))
	if err != nil {
		t.Fatalf("Write: %v", err)
	}

	// Read output
	buf := make([]byte, 4096)
	var output bytes.Buffer
	deadline := time.After(3 * time.Second)

	for {
		select {
		case <-deadline:
			if !bytes.Contains(output.Bytes(), []byte("hello")) {
				t.Fatalf("timeout: output was %q", output.String())
			}
			return
		default:
			sess.SetReadDeadline(time.Now().Add(100 * time.Millisecond))
			n, err := sess.Read(buf)
			if n > 0 {
				output.Write(buf[:n])
				if bytes.Contains(output.Bytes(), []byte("hello")) {
					return
				}
			}
			if err != nil {
				continue
			}
		}
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
go test ./internal/terminal/ -v -run TestSessionSpawnAndWrite
```

Expected: FAIL — package doesn't exist.

- [ ] **Step 3: Add PTY dependency**

```bash
go get github.com/creack/pty
```

- [ ] **Step 4: Implement session.go**

Create `internal/terminal/session.go`:
```go
package terminal

import (
	"io"
	"os"
	"sync"
	"time"
)

type Session struct {
	id       string
	pty      *os.File
	cols     uint16
	rows     uint16
	mu       sync.Mutex
	closed   bool
	deadline time.Time
}

func NewSession(cols, rows uint16) (*Session, error) {
	return newPlatformSession(cols, rows)
}

func (s *Session) ID() string {
	return s.id
}

func (s *Session) Write(p []byte) (int, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.closed {
		return 0, io.ErrClosedPipe
	}
	return s.pty.Write(p)
}

func (s *Session) Read(p []byte) (int, error) {
	return s.pty.Read(p)
}

func (s *Session) SetReadDeadline(t time.Time) {
	s.deadline = t
	s.pty.SetReadDeadline(t)
}

func (s *Session) Resize(cols, rows uint16) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.cols = cols
	s.rows = rows
	return s.resizePty(cols, rows)
}

func (s *Session) Close() error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.closed {
		return nil
	}
	s.closed = true
	return s.pty.Close()
}
```

- [ ] **Step 5: Implement pty_unix.go**

Create `internal/terminal/pty_unix.go`:
```go
//go:build !windows

package terminal

import (
	"crypto/rand"
	"encoding/hex"
	"os"
	"os/exec"

	"github.com/creack/pty"
)

func newPlatformSession(cols, rows uint16) (*Session, error) {
	shell := os.Getenv("SHELL")
	if shell == "" {
		shell = "/bin/sh"
	}

	cmd := exec.Command(shell)
	cmd.Env = append(os.Environ(), "TERM=xterm-256color")

	ptmx, err := pty.StartWithSize(cmd, &pty.Winsize{
		Cols: cols,
		Rows: rows,
	})
	if err != nil {
		return nil, err
	}

	id := make([]byte, 16)
	rand.Read(id)

	return &Session{
		id:   hex.EncodeToString(id),
		pty:  ptmx,
		cols: cols,
		rows: rows,
	}, nil
}

func (s *Session) resizePty(cols, rows uint16) error {
	return pty.Setsize(s.pty, &pty.Winsize{Cols: cols, Rows: rows})
}
```

- [ ] **Step 6: Implement pty_windows.go**

Create `internal/terminal/pty_windows.go`:
```go
//go:build windows

package terminal

import (
	"crypto/rand"
	"encoding/hex"
	"os"
	"os/exec"
	"syscall"
	"unsafe"
)

var (
	kernel32                    = syscall.NewLazyDLL("kernel32.dll")
	procCreatePseudoConsole    = kernel32.NewProc("CreatePseudoConsole")
	procResizePseudoConsole    = kernel32.NewProc("ResizePseudoConsole")
	procClosePseudoConsole     = kernel32.NewProc("ClosePseudoConsole")
)

type conPTY struct {
	handle   syscall.Handle
	inPipe   *os.File
	outPipe  *os.File
	cmd      *exec.Cmd
}

func newPlatformSession(cols, rows uint16) (*Session, error) {
	// Create pipes for ConPTY
	inRead, inWrite, err := os.Pipe()
	if err != nil {
		return nil, err
	}
	outRead, outWrite, err := os.Pipe()
	if err != nil {
		inRead.Close()
		inWrite.Close()
		return nil, err
	}

	// Create pseudo console
	coord := uintptr(cols) | (uintptr(rows) << 16)
	var hPC syscall.Handle
	ret, _, err := procCreatePseudoConsole.Call(
		coord,
		uintptr(inRead.Fd()),
		uintptr(outWrite.Fd()),
		0,
		uintptr(unsafe.Pointer(&hPC)),
	)
	if ret != 0 {
		inRead.Close()
		inWrite.Close()
		outRead.Close()
		outWrite.Close()
		return nil, err
	}

	// Close the ends we gave to ConPTY
	inRead.Close()
	outWrite.Close()

	// Start process attached to ConPTY
	shell := os.Getenv("COMSPEC")
	if shell == "" {
		shell = "cmd.exe"
	}

	cmd := exec.Command(shell)
	cmd.Env = append(os.Environ(), "TERM=xterm-256color")
	cmd.SysProcAttr = &syscall.SysProcAttr{
		CreationFlags: syscall.CREATE_UNICODE_ENVIRONMENT,
	}

	// For Windows ConPTY, we use the pipes directly
	// The outRead pipe gives us terminal output
	// The inWrite pipe accepts terminal input

	id := make([]byte, 16)
	rand.Read(id)

	sess := &Session{
		id:   hex.EncodeToString(id),
		pty:  outRead,  // read terminal output from here
		cols: cols,
		rows: rows,
	}

	// Store inWrite for writing (we'll use a wrapper)
	// For simplicity in the cross-platform interface, we use outRead as the "pty"
	// and override Write to use inWrite
	sess.pty = &winPtyFile{
		in:     inWrite,
		out:    outRead,
		handle: hPC,
		cmd:    cmd,
	}

	return sess, nil
}

// winPtyFile wraps ConPTY pipes to implement *os.File-like interface
type winPtyFile struct {
	in     *os.File
	out    *os.File
	handle syscall.Handle
	cmd    *exec.Cmd
}

func (s *Session) resizePty(cols, rows uint16) error {
	coord := uintptr(cols) | (uintptr(rows) << 16)
	ret, _, err := procResizePseudoConsole.Call(
		uintptr(s.pty.(*winPtyFile).handle),
		coord,
	)
	if ret != 0 {
		return err
	}
	return nil
}
```

**Note:** The Windows implementation above is a simplified skeleton. For production, we'll use `github.com/UserExitworktree/conpty` or refactor to use `golang.org/x/sys/windows`. This will be refined in Phase 9 (polish).

- [ ] **Step 7: Run test (Unix only for now)**

```bash
go test ./internal/terminal/ -v -run TestSessionSpawnAndWrite
```

Expected: PASS on Unix/WSL. On Windows native, skip for now (ConPTY needs refinement).

- [ ] **Step 8: Connect PTY to WebSocket**

Modify `internal/server/websocket.go`:
```go
package server

import (
	"encoding/json"
	"log"
	"net/http"

	"github.com/gorilla/websocket"
	"github.com/valorisa/ShellFromBrowser/internal/terminal"
)

var upgrader = websocket.Upgrader{
	CheckOrigin: func(r *http.Request) bool { return true },
}

type resizeMsg struct {
	Type string `json:"type"`
	Cols uint16 `json:"cols"`
	Rows uint16 `json:"rows"`
}

func (s *Server) handleWebSocket(w http.ResponseWriter, r *http.Request) {
	conn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		log.Printf("websocket upgrade: %v", err)
		return
	}
	defer conn.Close()

	sess, err := terminal.NewSession(80, 24)
	if err != nil {
		log.Printf("session create: %v", err)
		conn.WriteMessage(websocket.TextMessage, []byte("Failed to create session: "+err.Error()))
		return
	}
	defer sess.Close()

	// PTY -> WebSocket
	go func() {
		buf := make([]byte, 4096)
		for {
			n, err := sess.Read(buf)
			if err != nil {
				conn.WriteMessage(websocket.CloseMessage, websocket.FormatCloseMessage(1000, "session closed"))
				return
			}
			if err := conn.WriteMessage(websocket.BinaryMessage, buf[:n]); err != nil {
				return
			}
		}
	}()

	// WebSocket -> PTY
	for {
		msgType, msg, err := conn.ReadMessage()
		if err != nil {
			break
		}

		if msgType == websocket.TextMessage {
			var resize resizeMsg
			if json.Unmarshal(msg, &resize) == nil && resize.Type == "resize" {
				sess.Resize(resize.Cols, resize.Rows)
				continue
			}
		}

		sess.Write(msg)
	}
}
```

- [ ] **Step 9: Build and test in browser**

```bash
cd ShellFromBrowser
go build -o bin/shellfb.exe ./cmd/shellfb && ./bin/shellfb.exe
```

Open `http://localhost:8080` — should show a working interactive terminal (cmd.exe or shell).

- [ ] **Step 10: Commit**

```bash
git add internal/terminal/ internal/server/websocket.go go.mod go.sum
git commit -m "feat: add cross-platform PTY spawning connected to WebSocket"
```

---

## Phase 2: Authentication + TLS

### Task 5: Configuration system (YAML)

**Files:**
- Create: `internal/config/config.go`
- Create: `internal/config/config_test.go`
- Create: `config.example.yaml`

- [ ] **Step 1: Write the failing test**

Create `internal/config/config_test.go`:
```go
package config_test

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/valorisa/ShellFromBrowser/internal/config"
)

func TestLoadConfig(t *testing.T) {
	yaml := `
server:
  addr: ":9090"
  tls:
    enabled: true
    cert: "/etc/ssl/cert.pem"
    key: "/etc/ssl/key.pem"
auth:
  enabled: true
  users:
    - username: admin
      password_hash: "$2a$10$abcdefghijklmnopqrstuuxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
shell:
  command: "/bin/bash"
  env:
    - "TERM=xterm-256color"
sessions:
  max_per_user: 5
  idle_timeout: "30m"
ssh:
  enabled: true
  known_hosts: "~/.ssh/known_hosts"
recording:
  enabled: true
  dir: "./recordings"
`
	dir := t.TempDir()
	path := filepath.Join(dir, "config.yaml")
	os.WriteFile(path, []byte(yaml), 0644)

	cfg, err := config.Load(path)
	if err != nil {
		t.Fatalf("Load: %v", err)
	}

	if cfg.Server.Addr != ":9090" {
		t.Errorf("addr = %q, want :9090", cfg.Server.Addr)
	}
	if !cfg.Server.TLS.Enabled {
		t.Error("TLS should be enabled")
	}
	if !cfg.Auth.Enabled {
		t.Error("Auth should be enabled")
	}
	if len(cfg.Auth.Users) != 1 {
		t.Errorf("users = %d, want 1", len(cfg.Auth.Users))
	}
	if cfg.Sessions.MaxPerUser != 5 {
		t.Errorf("max_per_user = %d, want 5", cfg.Sessions.MaxPerUser)
	}
}

func TestLoadConfigDefaults(t *testing.T) {
	cfg := config.Default()
	if cfg.Server.Addr != ":8080" {
		t.Errorf("default addr = %q, want :8080", cfg.Server.Addr)
	}
	if cfg.Auth.Enabled {
		t.Error("auth should be disabled by default")
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
go get gopkg.in/yaml.v3
go test ./internal/config/ -v
```

Expected: FAIL

- [ ] **Step 3: Implement config.go**

Create `internal/config/config.go`:
```go
package config

import (
	"os"
	"time"

	"gopkg.in/yaml.v3"
)

type Config struct {
	Server    ServerConfig    `yaml:"server"`
	Auth      AuthConfig      `yaml:"auth"`
	Shell     ShellConfig     `yaml:"shell"`
	Sessions  SessionsConfig  `yaml:"sessions"`
	SSH       SSHConfig       `yaml:"ssh"`
	Recording RecordingConfig `yaml:"recording"`
}

type ServerConfig struct {
	Addr string    `yaml:"addr"`
	TLS  TLSConfig `yaml:"tls"`
}

type TLSConfig struct {
	Enabled bool   `yaml:"enabled"`
	Cert    string `yaml:"cert"`
	Key     string `yaml:"key"`
}

type AuthConfig struct {
	Enabled bool       `yaml:"enabled"`
	Users   []UserDef  `yaml:"users"`
	JWTSecret string  `yaml:"jwt_secret"`
}

type UserDef struct {
	Username     string `yaml:"username"`
	PasswordHash string `yaml:"password_hash"`
}

type ShellConfig struct {
	Command string   `yaml:"command"`
	Env     []string `yaml:"env"`
}

type SessionsConfig struct {
	MaxPerUser  int           `yaml:"max_per_user"`
	IdleTimeout time.Duration `yaml:"idle_timeout"`
}

type SSHConfig struct {
	Enabled    bool   `yaml:"enabled"`
	KnownHosts string `yaml:"known_hosts"`
}

type RecordingConfig struct {
	Enabled bool   `yaml:"enabled"`
	Dir     string `yaml:"dir"`
}

func Default() *Config {
	return &Config{
		Server: ServerConfig{Addr: ":8080"},
		Shell: ShellConfig{
			Env: []string{"TERM=xterm-256color"},
		},
		Sessions: SessionsConfig{
			MaxPerUser:  10,
			IdleTimeout: 30 * time.Minute,
		},
	}
}

func Load(path string) (*Config, error) {
	cfg := Default()
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	if err := yaml.Unmarshal(data, cfg); err != nil {
		return nil, err
	}
	return cfg, nil
}
```

- [ ] **Step 4: Run tests**

```bash
go test ./internal/config/ -v
```

Expected: PASS

- [ ] **Step 5: Create example config**

Create `config.example.yaml`:
```yaml
# ShellFromBrowser configuration
server:
  addr: ":8080"
  tls:
    enabled: false
    cert: ""
    key: ""

auth:
  enabled: false
  jwt_secret: "change-me-to-a-random-string"
  users:
    - username: admin
      # Generate with: shellfb hash-password
      password_hash: ""

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
  enabled: false
  dir: "./recordings"
```

- [ ] **Step 6: Commit**

```bash
git add internal/config/ config.example.yaml go.mod go.sum
git commit -m "feat: add YAML configuration system with defaults"
```

---

### Task 6: Authentication (JWT + bcrypt)

**Files:**
- Create: `internal/auth/auth.go`
- Create: `internal/auth/local.go`
- Create: `internal/auth/auth_test.go`
- Modify: `internal/server/server.go`

- [ ] **Step 1: Write the failing test**

Create `internal/auth/auth_test.go`:
```go
package auth_test

import (
	"testing"
	"time"

	"github.com/valorisa/ShellFromBrowser/internal/auth"
	"github.com/valorisa/ShellFromBrowser/internal/config"
)

func TestLocalAuth(t *testing.T) {
	hash, err := auth.HashPassword("secret123")
	if err != nil {
		t.Fatalf("HashPassword: %v", err)
	}

	cfg := &config.AuthConfig{
		Enabled:   true,
		JWTSecret: "test-secret-key",
		Users: []config.UserDef{
			{Username: "admin", PasswordHash: hash},
		},
	}

	provider := auth.NewLocalProvider(cfg)

	// Valid credentials
	token, err := provider.Authenticate("admin", "secret123")
	if err != nil {
		t.Fatalf("Authenticate valid: %v", err)
	}
	if token == "" {
		t.Fatal("token is empty")
	}

	// Validate token
	claims, err := provider.ValidateToken(token)
	if err != nil {
		t.Fatalf("ValidateToken: %v", err)
	}
	if claims.Username != "admin" {
		t.Errorf("username = %q, want admin", claims.Username)
	}

	// Invalid password
	_, err = provider.Authenticate("admin", "wrong")
	if err == nil {
		t.Fatal("expected error for wrong password")
	}

	// Invalid username
	_, err = provider.Authenticate("nobody", "secret123")
	if err == nil {
		t.Fatal("expected error for unknown user")
	}
}

func TestTokenExpiry(t *testing.T) {
	cfg := &config.AuthConfig{
		Enabled:   true,
		JWTSecret: "test-secret",
		Users:     []config.UserDef{{Username: "u", PasswordHash: ""}},
	}
	provider := auth.NewLocalProvider(cfg)
	provider.SetTokenDuration(1 * time.Millisecond)

	token, _ := provider.Authenticate("u", "")
	time.Sleep(10 * time.Millisecond)

	_, err := provider.ValidateToken(token)
	if err == nil {
		t.Fatal("expected expired token error")
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
go get github.com/golang-jwt/jwt/v5
go get golang.org/x/crypto/bcrypt
go test ./internal/auth/ -v
```

Expected: FAIL

- [ ] **Step 3: Implement auth.go**

Create `internal/auth/auth.go`:
```go
package auth

import (
	"errors"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"golang.org/x/crypto/bcrypt"
)

var (
	ErrInvalidCredentials = errors.New("invalid credentials")
	ErrTokenExpired       = errors.New("token expired")
	ErrTokenInvalid       = errors.New("token invalid")
)

type Claims struct {
	Username string `json:"username"`
	jwt.RegisteredClaims
}

type Provider interface {
	Authenticate(username, password string) (token string, err error)
	ValidateToken(token string) (*Claims, error)
}

func HashPassword(password string) (string, error) {
	bytes, err := bcrypt.GenerateFromPassword([]byte(password), bcrypt.DefaultCost)
	return string(bytes), err
}

func CheckPassword(password, hash string) bool {
	err := bcrypt.CompareHashAndPassword([]byte(hash), []byte(password))
	return err == nil
}
```

- [ ] **Step 4: Implement local.go**

Create `internal/auth/local.go`:
```go
package auth

import (
	"time"

	"github.com/golang-jwt/jwt/v5"
	"github.com/valorisa/ShellFromBrowser/internal/config"
)

type LocalProvider struct {
	users         map[string]string // username -> password_hash
	jwtSecret     []byte
	tokenDuration time.Duration
}

func NewLocalProvider(cfg *config.AuthConfig) *LocalProvider {
	users := make(map[string]string)
	for _, u := range cfg.Users {
		users[u.Username] = u.PasswordHash
	}
	return &LocalProvider{
		users:         users,
		jwtSecret:     []byte(cfg.JWTSecret),
		tokenDuration: 24 * time.Hour,
	}
}

func (p *LocalProvider) SetTokenDuration(d time.Duration) {
	p.tokenDuration = d
}

func (p *LocalProvider) Authenticate(username, password string) (string, error) {
	hash, exists := p.users[username]
	if !exists {
		return "", ErrInvalidCredentials
	}

	if hash != "" && !CheckPassword(password, hash) {
		return "", ErrInvalidCredentials
	}

	claims := &Claims{
		Username: username,
		RegisteredClaims: jwt.RegisteredClaims{
			ExpiresAt: jwt.NewNumericDate(time.Now().Add(p.tokenDuration)),
			IssuedAt:  jwt.NewNumericDate(time.Now()),
		},
	}

	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	return token.SignedString(p.jwtSecret)
}

func (p *LocalProvider) ValidateToken(tokenStr string) (*Claims, error) {
	claims := &Claims{}
	token, err := jwt.ParseWithClaims(tokenStr, claims, func(t *jwt.Token) (interface{}, error) {
		return p.jwtSecret, nil
	})
	if err != nil {
		return nil, ErrTokenInvalid
	}
	if !token.Valid {
		return nil, ErrTokenExpired
	}
	return claims, nil
}
```

- [ ] **Step 5: Run tests**

```bash
go test ./internal/auth/ -v
```

Expected: PASS

- [ ] **Step 6: Add login endpoint and auth middleware to server**

Modify `internal/server/server.go` — add login route and middleware:
```go
package server

import (
	"encoding/json"
	"io/fs"
	"net/http"
	"strings"

	"github.com/valorisa/ShellFromBrowser/internal/auth"
	"github.com/valorisa/ShellFromBrowser/internal/config"
	"github.com/valorisa/ShellFromBrowser/web"
)

type Server struct {
	addr     string
	mux      *http.ServeMux
	cfg      *config.Config
	authProv auth.Provider
}

func New(addr string, cfg *config.Config) *Server {
	s := &Server{addr: addr, mux: http.NewServeMux(), cfg: cfg}

	if cfg.Auth.Enabled {
		s.authProv = auth.NewLocalProvider(&cfg.Auth)
	}

	// API routes
	s.mux.HandleFunc("/api/login", s.handleLogin)
	s.mux.HandleFunc("/ws", s.authMiddleware(s.handleWebSocket))

	// Static files
	staticFS, _ := fs.Sub(web.StaticFiles, "static")
	s.mux.Handle("/static/", http.StripPrefix("/static/", http.FileServer(http.FS(staticFS))))
	s.mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/" {
			http.NotFound(w, r)
			return
		}
		data, _ := web.StaticFiles.ReadFile("static/index.html")
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		w.Write(data)
	})

	return s
}

func (s *Server) Handler() http.Handler {
	return s.mux
}

func (s *Server) ListenAndServe() error {
	if s.cfg.Server.TLS.Enabled {
		return http.ListenAndServeTLS(s.addr, s.cfg.Server.TLS.Cert, s.cfg.Server.TLS.Key, s.mux)
	}
	return http.ListenAndServe(s.addr, s.mux)
}

type loginRequest struct {
	Username string `json:"username"`
	Password string `json:"password"`
}

type loginResponse struct {
	Token string `json:"token"`
	Error string `json:"error,omitempty"`
}

func (s *Server) handleLogin(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var req loginRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, loginResponse{Error: "invalid request"})
		return
	}

	if s.authProv == nil {
		writeJSON(w, http.StatusOK, loginResponse{Token: "no-auth"})
		return
	}

	token, err := s.authProv.Authenticate(req.Username, req.Password)
	if err != nil {
		writeJSON(w, http.StatusUnauthorized, loginResponse{Error: "invalid credentials"})
		return
	}

	writeJSON(w, http.StatusOK, loginResponse{Token: token})
}

func (s *Server) authMiddleware(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if s.authProv == nil {
			next(w, r)
			return
		}

		token := r.URL.Query().Get("token")
		if token == "" {
			authHeader := r.Header.Get("Authorization")
			token = strings.TrimPrefix(authHeader, "Bearer ")
		}

		if token == "" {
			http.Error(w, "unauthorized", http.StatusUnauthorized)
			return
		}

		_, err := s.authProv.ValidateToken(token)
		if err != nil {
			http.Error(w, "unauthorized", http.StatusUnauthorized)
			return
		}

		next(w, r)
	}
}

func writeJSON(w http.ResponseWriter, status int, v interface{}) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(v)
}
```

- [ ] **Step 7: Update main.go to pass config**

```go
package main

import (
	"flag"
	"fmt"
	"log"
	"os"
	"os/signal"
	"syscall"

	"github.com/valorisa/ShellFromBrowser/internal/config"
	"github.com/valorisa/ShellFromBrowser/internal/server"
)

var (
	version = "dev"
	commit  = "none"
)

func main() {
	addr := flag.String("addr", "", "listen address (overrides config)")
	configPath := flag.String("config", "", "path to config file")
	showVersion := flag.Bool("version", false, "print version and exit")
	flag.Parse()

	if *showVersion {
		fmt.Printf("ShellFromBrowser %s (%s)\n", version, commit)
		os.Exit(0)
	}

	var cfg *config.Config
	var err error
	if *configPath != "" {
		cfg, err = config.Load(*configPath)
		if err != nil {
			log.Fatalf("config: %v", err)
		}
	} else {
		cfg = config.Default()
	}

	if *addr != "" {
		cfg.Server.Addr = *addr
	}

	srv := server.New(cfg.Server.Addr, cfg)
	log.Printf("ShellFromBrowser %s starting on %s", version, cfg.Server.Addr)

	go func() {
		if err := srv.ListenAndServe(); err != nil {
			log.Fatalf("server: %v", err)
		}
	}()

	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit
	log.Println("shutting down")
}
```

- [ ] **Step 8: Commit**

```bash
git add internal/auth/ internal/server/ cmd/shellfb/main.go go.mod go.sum
git commit -m "feat: add JWT authentication with login endpoint and auth middleware"
```

---

## Phase 3: Multi-Sessions + Reconnection

### Task 7: Session manager

**Files:**
- Create: `internal/terminal/manager.go`
- Modify: `internal/terminal/session_test.go`
- Modify: `internal/server/websocket.go`

- [ ] **Step 1: Write the failing test**

Add to `internal/terminal/session_test.go`:
```go
func TestSessionManager(t *testing.T) {
	mgr := terminal.NewManager(5)

	// Create sessions
	s1, err := mgr.Create("user1", 80, 24)
	if err != nil {
		t.Fatalf("Create: %v", err)
	}

	s2, err := mgr.Create("user1", 80, 24)
	if err != nil {
		t.Fatalf("Create: %v", err)
	}

	// List sessions
	sessions := mgr.ListByUser("user1")
	if len(sessions) != 2 {
		t.Errorf("ListByUser = %d, want 2", len(sessions))
	}

	// Get by ID
	got, err := mgr.Get(s1.ID())
	if err != nil {
		t.Fatalf("Get: %v", err)
	}
	if got.ID() != s1.ID() {
		t.Error("Get returned wrong session")
	}

	// Destroy
	mgr.Destroy(s2.ID())
	sessions = mgr.ListByUser("user1")
	if len(sessions) != 1 {
		t.Errorf("after destroy: %d, want 1", len(sessions))
	}
}

func TestSessionManagerMaxSessions(t *testing.T) {
	mgr := terminal.NewManager(2)

	mgr.Create("user1", 80, 24)
	mgr.Create("user1", 80, 24)
	_, err := mgr.Create("user1", 80, 24)
	if err == nil {
		t.Fatal("expected max sessions error")
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
go test ./internal/terminal/ -v -run TestSessionManager
```

Expected: FAIL

- [ ] **Step 3: Implement manager.go**

Create `internal/terminal/manager.go`:
```go
package terminal

import (
	"errors"
	"sync"
)

var ErrMaxSessions = errors.New("maximum sessions reached")

type SessionInfo struct {
	ID   string
	User string
	Cols uint16
	Rows uint16
}

type Manager struct {
	sessions    map[string]*Session
	userIndex   map[string][]string // username -> []session_id
	maxPerUser  int
	mu          sync.RWMutex
}

func NewManager(maxPerUser int) *Manager {
	return &Manager{
		sessions:   make(map[string]*Session),
		userIndex:  make(map[string][]string),
		maxPerUser: maxPerUser,
	}
}

func (m *Manager) Create(username string, cols, rows uint16) (*Session, error) {
	m.mu.Lock()
	defer m.mu.Unlock()

	if len(m.userIndex[username]) >= m.maxPerUser {
		return nil, ErrMaxSessions
	}

	sess, err := NewSession(cols, rows)
	if err != nil {
		return nil, err
	}

	m.sessions[sess.ID()] = sess
	m.userIndex[username] = append(m.userIndex[username], sess.ID())
	return sess, nil
}

func (m *Manager) Get(id string) (*Session, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()

	sess, ok := m.sessions[id]
	if !ok {
		return nil, errors.New("session not found")
	}
	return sess, nil
}

func (m *Manager) ListByUser(username string) []SessionInfo {
	m.mu.RLock()
	defer m.mu.RUnlock()

	var infos []SessionInfo
	for _, id := range m.userIndex[username] {
		if sess, ok := m.sessions[id]; ok {
			infos = append(infos, SessionInfo{
				ID:   sess.ID(),
				User: username,
				Cols: sess.cols,
				Rows: sess.rows,
			})
		}
	}
	return infos
}

func (m *Manager) Destroy(id string) {
	m.mu.Lock()
	defer m.mu.Unlock()

	sess, ok := m.sessions[id]
	if !ok {
		return
	}
	sess.Close()
	delete(m.sessions, id)

	for user, ids := range m.userIndex {
		for i, sid := range ids {
			if sid == id {
				m.userIndex[user] = append(ids[:i], ids[i+1:]...)
				break
			}
		}
	}
}

func (m *Manager) DestroyAll() {
	m.mu.Lock()
	defer m.mu.Unlock()

	for _, sess := range m.sessions {
		sess.Close()
	}
	m.sessions = make(map[string]*Session)
	m.userIndex = make(map[string][]string)
}
```

- [ ] **Step 4: Run tests**

```bash
go test ./internal/terminal/ -v -run TestSessionManager
```

Expected: PASS

- [ ] **Step 5: Update WebSocket handler for multi-session**

Modify `internal/server/websocket.go` to support session create/attach/list via query params:
```go
package server

import (
	"encoding/json"
	"log"
	"net/http"

	"github.com/gorilla/websocket"
	"github.com/valorisa/ShellFromBrowser/internal/terminal"
)

var upgrader = websocket.Upgrader{
	CheckOrigin: func(r *http.Request) bool { return true },
}

type wsMessage struct {
	Type string `json:"type"`
	Cols uint16 `json:"cols,omitempty"`
	Rows uint16 `json:"rows,omitempty"`
}

func (s *Server) handleWebSocket(w http.ResponseWriter, r *http.Request) {
	conn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		log.Printf("websocket upgrade: %v", err)
		return
	}
	defer conn.Close()

	username := "anonymous"
	if s.authProv != nil {
		token := r.URL.Query().Get("token")
		claims, _ := s.authProv.ValidateToken(token)
		if claims != nil {
			username = claims.Username
		}
	}

	sessionID := r.URL.Query().Get("session")
	var sess *terminal.Session

	if sessionID != "" {
		sess, err = s.sessions.Get(sessionID)
		if err != nil {
			conn.WriteMessage(websocket.TextMessage, []byte(`{"type":"error","message":"session not found"}`))
			return
		}
	} else {
		sess, err = s.sessions.Create(username, 80, 24)
		if err != nil {
			conn.WriteMessage(websocket.TextMessage, []byte(`{"type":"error","message":"`+err.Error()+`"}`))
			return
		}
	}

	// Send session info
	info, _ := json.Marshal(map[string]string{"type": "session", "id": sess.ID()})
	conn.WriteMessage(websocket.TextMessage, info)

	// PTY -> WebSocket
	done := make(chan struct{})
	go func() {
		defer close(done)
		buf := make([]byte, 4096)
		for {
			n, err := sess.Read(buf)
			if err != nil {
				return
			}
			if err := conn.WriteMessage(websocket.BinaryMessage, buf[:n]); err != nil {
				return
			}
		}
	}()

	// WebSocket -> PTY
	for {
		msgType, msg, err := conn.ReadMessage()
		if err != nil {
			break
		}

		if msgType == websocket.TextMessage {
			var wsMsg wsMessage
			if json.Unmarshal(msg, &wsMsg) == nil {
				switch wsMsg.Type {
				case "resize":
					sess.Resize(wsMsg.Cols, wsMsg.Rows)
					continue
				}
			}
		}

		sess.Write(msg)
	}

	<-done
}

func (s *Server) handleSessions(w http.ResponseWriter, r *http.Request) {
	username := "anonymous"
	if s.authProv != nil {
		token := r.URL.Query().Get("token")
		if token == "" {
			token = r.Header.Get("Authorization")
			if len(token) > 7 {
				token = token[7:]
			}
		}
		claims, err := s.authProv.ValidateToken(token)
		if err != nil {
			http.Error(w, "unauthorized", http.StatusUnauthorized)
			return
		}
		username = claims.Username
	}

	switch r.Method {
	case http.MethodGet:
		sessions := s.sessions.ListByUser(username)
		writeJSON(w, http.StatusOK, sessions)
	case http.MethodDelete:
		id := r.URL.Query().Get("id")
		if id != "" {
			s.sessions.Destroy(id)
		}
		w.WriteHeader(http.StatusNoContent)
	default:
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
	}
}
```

- [ ] **Step 6: Add sessions field and route to Server**

Update `internal/server/server.go` — add `sessions *terminal.Manager` field and `/api/sessions` route:
```go
// In New():
s.sessions = terminal.NewManager(cfg.Sessions.MaxPerUser)
s.mux.HandleFunc("/api/sessions", s.authMiddleware(s.handleSessions))
```

Add field to struct:
```go
type Server struct {
	addr     string
	mux      *http.ServeMux
	cfg      *config.Config
	authProv auth.Provider
	sessions *terminal.Manager
}
```

Add import:
```go
"github.com/valorisa/ShellFromBrowser/internal/terminal"
```

- [ ] **Step 7: Commit**

```bash
git add internal/terminal/manager.go internal/terminal/session_test.go internal/server/
git commit -m "feat: add session manager with multi-session support and session API"
```

---

### Task 8: Frontend multi-tab UI

**Files:**
- Modify: `web/static/index.html`
- Create: `web/static/js/sessions.js`
- Modify: `web/static/js/terminal.js`
- Modify: `web/static/css/app.css`

- [ ] **Step 1: Update HTML for tabs**

Replace `web/static/index.html`:
```html
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>ShellFromBrowser</title>
    <link rel="stylesheet" href="/static/css/xterm.css">
    <link rel="stylesheet" href="/static/css/app.css">
</head>
<body>
    <div id="login-screen" style="display:none;">
        <div class="login-box">
            <h1>ShellFromBrowser</h1>
            <form id="login-form">
                <input type="text" id="username" placeholder="Username" autocomplete="username">
                <input type="password" id="password" placeholder="Password" autocomplete="current-password">
                <button type="submit">Connect</button>
                <div id="login-error" class="error"></div>
            </form>
        </div>
    </div>

    <div id="app" style="display:none;">
        <div id="tab-bar">
            <div id="tabs"></div>
            <button id="new-tab" title="New session">+</button>
        </div>
        <div id="terminal-container">
            <div id="terminal"></div>
        </div>
        <div id="status-bar">
            <span id="session-info"></span>
            <span id="connection-status">Disconnected</span>
        </div>
    </div>

    <script src="/static/js/xterm.js"></script>
    <script src="/static/js/xterm-addon-fit.js"></script>
    <script src="/static/js/xterm-addon-web-links.js"></script>
    <script src="/static/js/sessions.js"></script>
    <script src="/static/js/terminal.js"></script>
</body>
</html>
```

- [ ] **Step 2: Create sessions.js**

Create `web/static/js/sessions.js`:
```javascript
var SessionManager = (function () {
    "use strict";

    var token = localStorage.getItem("sfb_token") || "";
    var sessions = [];
    var activeSessionId = null;

    function setToken(t) {
        token = t;
        localStorage.setItem("sfb_token", t);
    }

    function getToken() {
        return token;
    }

    function clearToken() {
        token = "";
        localStorage.removeItem("sfb_token");
    }

    async function login(username, password) {
        var resp = await fetch("/api/login", {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ username: username, password: password }),
        });
        var data = await resp.json();
        if (data.error) throw new Error(data.error);
        setToken(data.token);
        return data.token;
    }

    async function listSessions() {
        var resp = await fetch("/api/sessions?token=" + encodeURIComponent(token));
        if (resp.status === 401) {
            clearToken();
            return [];
        }
        sessions = await resp.json();
        return sessions;
    }

    function setActive(id) {
        activeSessionId = id;
    }

    function getActive() {
        return activeSessionId;
    }

    return {
        login: login,
        listSessions: listSessions,
        getToken: getToken,
        clearToken: clearToken,
        setActive: setActive,
        getActive: getActive,
    };
})();
```

- [ ] **Step 3: Update terminal.js for session management**

Replace `web/static/js/terminal.js`:
```javascript
(function () {
    "use strict";

    var terminals = {};
    var activeTermId = null;
    var tabIndex = 0;

    function createTerminal(sessionId) {
        var id = "term-" + (tabIndex++);
        var term = new Terminal({
            cursorBlink: true,
            fontSize: 14,
            fontFamily: "'JetBrains Mono', 'Fira Code', monospace",
            theme: {
                background: "#1e1e2e",
                foreground: "#cdd6f4",
                cursor: "#f5e0dc",
            },
        });

        var fitAddon = new FitAddon.FitAddon();
        var webLinksAddon = new WebLinksAddon.WebLinksAddon();
        term.loadAddon(fitAddon);
        term.loadAddon(webLinksAddon);

        var protocol = window.location.protocol === "https:" ? "wss:" : "ws:";
        var wsUrl = protocol + "//" + window.location.host + "/ws?token=" +
            encodeURIComponent(SessionManager.getToken());
        if (sessionId) wsUrl += "&session=" + encodeURIComponent(sessionId);

        var ws = new WebSocket(wsUrl);
        ws.binaryType = "arraybuffer";

        ws.onopen = function () {
            var dims = JSON.stringify({ type: "resize", cols: term.cols, rows: term.rows });
            ws.send(dims);
            setStatus("Connected");
        };

        ws.onmessage = function (event) {
            if (event.data instanceof ArrayBuffer) {
                term.write(new Uint8Array(event.data));
            } else {
                try {
                    var msg = JSON.parse(event.data);
                    if (msg.type === "session") {
                        terminals[id].sessionId = msg.id;
                        SessionManager.setActive(msg.id);
                        updateSessionInfo();
                    }
                } catch (e) {
                    term.write(event.data);
                }
            }
        };

        ws.onclose = function () { setStatus("Disconnected"); };

        term.onData(function (data) {
            if (ws.readyState === WebSocket.OPEN) ws.send(data);
        });

        term.onResize(function (size) {
            if (ws.readyState === WebSocket.OPEN) {
                ws.send(JSON.stringify({ type: "resize", cols: size.cols, rows: size.rows }));
            }
        });

        terminals[id] = { term: term, fitAddon: fitAddon, ws: ws, sessionId: sessionId || null };
        addTab(id);
        switchTab(id);

        return id;
    }

    function addTab(id) {
        var tabs = document.getElementById("tabs");
        var tab = document.createElement("div");
        tab.className = "tab";
        tab.dataset.id = id;
        tab.textContent = "Session " + (Object.keys(terminals).length);

        var closeBtn = document.createElement("span");
        closeBtn.className = "tab-close";
        closeBtn.textContent = "×";
        closeBtn.onclick = function (e) {
            e.stopPropagation();
            closeTab(id);
        };

        tab.appendChild(closeBtn);
        tab.onclick = function () { switchTab(id); };
        tabs.appendChild(tab);
    }

    function switchTab(id) {
        if (activeTermId && terminals[activeTermId]) {
            terminals[activeTermId].term.element.style.display = "none";
        }
        activeTermId = id;
        var t = terminals[id];
        var container = document.getElementById("terminal");

        if (!t.term.element) {
            t.term.open(container);
        } else {
            t.term.element.style.display = "";
            container.appendChild(t.term.element);
        }
        t.fitAddon.fit();
        t.term.focus();

        document.querySelectorAll(".tab").forEach(function (el) {
            el.classList.toggle("active", el.dataset.id === id);
        });

        if (t.sessionId) SessionManager.setActive(t.sessionId);
        updateSessionInfo();
    }

    function closeTab(id) {
        var t = terminals[id];
        if (t) {
            t.ws.close();
            t.term.dispose();
            delete terminals[id];
        }
        var tabEl = document.querySelector('.tab[data-id="' + id + '"]');
        if (tabEl) tabEl.remove();

        var remaining = Object.keys(terminals);
        if (remaining.length > 0) {
            switchTab(remaining[remaining.length - 1]);
        }
    }

    function setStatus(text) {
        document.getElementById("connection-status").textContent = text;
    }

    function updateSessionInfo() {
        var info = document.getElementById("session-info");
        var count = Object.keys(terminals).length;
        info.textContent = count + " session" + (count !== 1 ? "s" : "");
    }

    // Initialization
    function init() {
        var token = SessionManager.getToken();
        if (!token) {
            document.getElementById("login-screen").style.display = "flex";
        } else {
            startApp();
        }

        document.getElementById("login-form").onsubmit = async function (e) {
            e.preventDefault();
            var user = document.getElementById("username").value;
            var pass = document.getElementById("password").value;
            try {
                await SessionManager.login(user, pass);
                document.getElementById("login-screen").style.display = "none";
                startApp();
            } catch (err) {
                document.getElementById("login-error").textContent = err.message;
            }
        };
    }

    function startApp() {
        document.getElementById("app").style.display = "flex";
        createTerminal();

        document.getElementById("new-tab").onclick = function () {
            createTerminal();
        };

        window.addEventListener("resize", function () {
            if (activeTermId && terminals[activeTermId]) {
                terminals[activeTermId].fitAddon.fit();
            }
        });
    }

    // If auth is disabled, skip login
    fetch("/api/login", { method: "POST", headers: { "Content-Type": "application/json" }, body: "{}" })
        .then(function (r) { return r.json(); })
        .then(function (data) {
            if (data.token === "no-auth") {
                SessionManager.login("", "").then(function () { init(); });
            } else {
                init();
            }
        })
        .catch(function () { init(); });
})();
```

- [ ] **Step 4: Update CSS for tabs and login**

Replace `web/static/css/app.css`:
```css
* {
    margin: 0;
    padding: 0;
    box-sizing: border-box;
}

html, body {
    height: 100%;
    background: #1e1e2e;
    overflow: hidden;
    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
    color: #cdd6f4;
}

/* Login */
#login-screen {
    height: 100%;
    display: flex;
    align-items: center;
    justify-content: center;
}

.login-box {
    background: #313244;
    padding: 2rem;
    border-radius: 8px;
    width: 320px;
}

.login-box h1 {
    font-size: 1.4rem;
    margin-bottom: 1.5rem;
    text-align: center;
}

.login-box input {
    display: block;
    width: 100%;
    padding: 0.6rem;
    margin-bottom: 0.8rem;
    border: 1px solid #45475a;
    border-radius: 4px;
    background: #1e1e2e;
    color: #cdd6f4;
    font-size: 0.9rem;
}

.login-box button {
    width: 100%;
    padding: 0.6rem;
    background: #89b4fa;
    color: #1e1e2e;
    border: none;
    border-radius: 4px;
    font-size: 0.9rem;
    font-weight: 600;
    cursor: pointer;
}

.login-box button:hover {
    background: #74c7ec;
}

.error {
    color: #f38ba8;
    font-size: 0.85rem;
    margin-top: 0.5rem;
}

/* App layout */
#app {
    height: 100%;
    flex-direction: column;
}

#tab-bar {
    display: flex;
    align-items: center;
    background: #181825;
    padding: 4px 8px;
    gap: 4px;
}

#tabs {
    display: flex;
    gap: 2px;
    flex: 1;
    overflow-x: auto;
}

.tab {
    padding: 4px 12px;
    background: #313244;
    border-radius: 4px 4px 0 0;
    cursor: pointer;
    font-size: 0.8rem;
    white-space: nowrap;
    display: flex;
    align-items: center;
    gap: 6px;
}

.tab.active {
    background: #1e1e2e;
}

.tab-close {
    font-size: 1rem;
    opacity: 0.5;
    cursor: pointer;
}

.tab-close:hover {
    opacity: 1;
    color: #f38ba8;
}

#new-tab {
    background: none;
    border: 1px solid #45475a;
    color: #cdd6f4;
    border-radius: 4px;
    width: 24px;
    height: 24px;
    cursor: pointer;
    font-size: 1rem;
    display: flex;
    align-items: center;
    justify-content: center;
}

#new-tab:hover {
    background: #313244;
}

#terminal-container {
    flex: 1;
    padding: 4px;
    overflow: hidden;
}

#terminal {
    height: 100%;
}

#status-bar {
    display: flex;
    justify-content: space-between;
    padding: 2px 8px;
    background: #181825;
    font-size: 0.75rem;
    color: #6c7086;
}
```

- [ ] **Step 5: Test in browser**

```bash
cd ShellFromBrowser
go build -o bin/shellfb.exe ./cmd/shellfb && ./bin/shellfb.exe
```

Open `http://localhost:8080` — verify tabs work, new sessions open, close works.

- [ ] **Step 6: Commit**

```bash
git add web/
git commit -m "feat: add multi-tab session UI with login screen"
```

---

## Phase 4: SSH Client Integration

### Task 9: SSH client library

**Files:**
- Create: `internal/ssh/client.go`
- Create: `internal/ssh/known_hosts.go`
- Create: `internal/ssh/client_test.go`

- [ ] **Step 1: Write the failing test**

Create `internal/ssh/client_test.go`:
```go
package ssh_test

import (
	"testing"

	sshclient "github.com/valorisa/ShellFromBrowser/internal/ssh"
)

func TestParseTarget(t *testing.T) {
	tests := []struct {
		input    string
		wantUser string
		wantHost string
		wantPort string
	}{
		{"user@host.com", "user", "host.com", "22"},
		{"user@host.com:2222", "user", "host.com", "2222"},
		{"host.com", "", "host.com", "22"},
		{"root@192.168.1.1:22", "root", "192.168.1.1", "22"},
	}

	for _, tt := range tests {
		user, host, port := sshclient.ParseTarget(tt.input)
		if user != tt.wantUser || host != tt.wantHost || port != tt.wantPort {
			t.Errorf("ParseTarget(%q) = (%q,%q,%q), want (%q,%q,%q)",
				tt.input, user, host, port, tt.wantUser, tt.wantHost, tt.wantPort)
		}
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
go get golang.org/x/crypto/ssh
go test ./internal/ssh/ -v -run TestParseTarget
```

Expected: FAIL

- [ ] **Step 3: Implement client.go**

Create `internal/ssh/client.go`:
```go
package ssh

import (
	"fmt"
	"io"
	"net"
	"strings"

	gossh "golang.org/x/crypto/ssh"
)

type ConnectOpts struct {
	Target   string // user@host:port
	Password string
	KeyFile  string
	Cols     uint32
	Rows     uint32
}

type SSHSession struct {
	client  *gossh.Client
	session *gossh.Session
	stdin   io.WriteCloser
	stdout  io.Reader
}

func ParseTarget(target string) (user, host, port string) {
	port = "22"

	if at := strings.LastIndex(target, "@"); at >= 0 {
		user = target[:at]
		target = target[at+1:]
	}

	if colon := strings.LastIndex(target, ":"); colon >= 0 {
		host = target[:colon]
		port = target[colon+1:]
	} else {
		host = target
	}
	return
}

func Connect(opts ConnectOpts) (*SSHSession, error) {
	user, host, port := ParseTarget(opts.Target)
	if user == "" {
		user = "root"
	}

	var authMethods []gossh.AuthMethod
	if opts.Password != "" {
		authMethods = append(authMethods, gossh.Password(opts.Password))
	}
	if opts.KeyFile != "" {
		if signer, err := loadKey(opts.KeyFile); err == nil {
			authMethods = append(authMethods, gossh.PublicKeys(signer))
		}
	}

	config := &gossh.ClientConfig{
		User:            user,
		Auth:            authMethods,
		HostKeyCallback: gossh.InsecureIgnoreHostKey(), // TODO: replace with known_hosts
	}

	addr := net.JoinHostPort(host, port)
	client, err := gossh.Dial("tcp", addr, config)
	if err != nil {
		return nil, fmt.Errorf("ssh dial: %w", err)
	}

	session, err := client.NewSession()
	if err != nil {
		client.Close()
		return nil, fmt.Errorf("ssh session: %w", err)
	}

	modes := gossh.TerminalModes{
		gossh.ECHO:          1,
		gossh.TTY_OP_ISPEED: 14400,
		gossh.TTY_OP_OSPEED: 14400,
	}

	if err := session.RequestPty("xterm-256color", int(opts.Rows), int(opts.Cols), modes); err != nil {
		session.Close()
		client.Close()
		return nil, fmt.Errorf("request pty: %w", err)
	}

	stdin, err := session.StdinPipe()
	if err != nil {
		session.Close()
		client.Close()
		return nil, err
	}

	stdout, err := session.StdoutPipe()
	if err != nil {
		session.Close()
		client.Close()
		return nil, err
	}

	if err := session.Shell(); err != nil {
		session.Close()
		client.Close()
		return nil, fmt.Errorf("start shell: %w", err)
	}

	return &SSHSession{
		client:  client,
		session: session,
		stdin:   stdin,
		stdout:  stdout,
	}, nil
}

func (s *SSHSession) Read(p []byte) (int, error) {
	return s.stdout.Read(p)
}

func (s *SSHSession) Write(p []byte) (int, error) {
	return s.stdin.Write(p)
}

func (s *SSHSession) Resize(cols, rows uint32) error {
	return s.session.WindowChange(int(rows), int(cols))
}

func (s *SSHSession) Close() error {
	s.stdin.Close()
	s.session.Close()
	return s.client.Close()
}

func loadKey(path string) (gossh.Signer, error) {
	// Read key file and parse
	import_os_readfile := func(p string) ([]byte, error) {
		return nil, fmt.Errorf("not implemented")
	}
	key, err := import_os_readfile(path)
	if err != nil {
		return nil, err
	}
	return gossh.ParsePrivateKey(key)
}
```

**Fix loadKey properly:**
```go
func loadKey(path string) (gossh.Signer, error) {
	key, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	return gossh.ParsePrivateKey(key)
}
```

(Add `"os"` to imports)

- [ ] **Step 4: Run tests**

```bash
go test ./internal/ssh/ -v -run TestParseTarget
```

Expected: PASS

- [ ] **Step 5: Add SSH WebSocket endpoint**

Add to `internal/server/server.go` a new route:
```go
s.mux.HandleFunc("/ws/ssh", s.authMiddleware(s.handleSSHWebSocket))
```

Create handler in `internal/server/websocket.go` (add to file):
```go
func (s *Server) handleSSHWebSocket(w http.ResponseWriter, r *http.Request) {
	conn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		return
	}
	defer conn.Close()

	target := r.URL.Query().Get("target")
	password := r.URL.Query().Get("password")
	keyFile := r.URL.Query().Get("key")

	if target == "" {
		conn.WriteMessage(websocket.TextMessage, []byte(`{"type":"error","message":"target required"}`))
		return
	}

	sshSess, err := ssh.Connect(ssh.ConnectOpts{
		Target:   target,
		Password: password,
		KeyFile:  keyFile,
		Cols:     80,
		Rows:     24,
	})
	if err != nil {
		conn.WriteMessage(websocket.TextMessage, []byte(`{"type":"error","message":"`+err.Error()+`"}`))
		return
	}
	defer sshSess.Close()

	// SSH stdout -> WebSocket
	go func() {
		buf := make([]byte, 4096)
		for {
			n, err := sshSess.Read(buf)
			if err != nil {
				return
			}
			conn.WriteMessage(websocket.BinaryMessage, buf[:n])
		}
	}()

	// WebSocket -> SSH stdin
	for {
		msgType, msg, err := conn.ReadMessage()
		if err != nil {
			break
		}
		if msgType == websocket.TextMessage {
			var wsMsg wsMessage
			if json.Unmarshal(msg, &wsMsg) == nil && wsMsg.Type == "resize" {
				sshSess.Resize(uint32(wsMsg.Cols), uint32(wsMsg.Rows))
				continue
			}
		}
		sshSess.Write(msg)
	}
}
```

Add import: `sshpkg "github.com/valorisa/ShellFromBrowser/internal/ssh"`

- [ ] **Step 6: Commit**

```bash
git add internal/ssh/ internal/server/
git commit -m "feat: add SSH client integration with WebSocket bridge"
```

---

## Phase 5: File Transfer

### Task 10: Upload and download handlers

**Files:**
- Create: `internal/transfer/upload.go`
- Create: `internal/transfer/download.go`
- Create: `internal/transfer/transfer_test.go`

- [ ] **Step 1: Write the failing test**

Create `internal/transfer/transfer_test.go`:
```go
package transfer_test

import (
	"bytes"
	"io"
	"mime/multipart"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"

	"github.com/valorisa/ShellFromBrowser/internal/transfer"
)

func TestUpload(t *testing.T) {
	uploadDir := t.TempDir()
	handler := transfer.NewHandler(uploadDir, 10*1024*1024) // 10MB max

	// Create multipart request
	var buf bytes.Buffer
	writer := multipart.NewWriter(&buf)
	part, _ := writer.CreateFormFile("file", "test.txt")
	part.Write([]byte("hello world"))
	writer.Close()

	req := httptest.NewRequest(http.MethodPost, "/api/upload", &buf)
	req.Header.Set("Content-Type", writer.FormDataContentType())
	w := httptest.NewRecorder()

	handler.Upload(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200. Body: %s", w.Code, w.Body.String())
	}

	// Verify file exists
	content, err := os.ReadFile(filepath.Join(uploadDir, "test.txt"))
	if err != nil {
		t.Fatalf("file not found: %v", err)
	}
	if string(content) != "hello world" {
		t.Errorf("content = %q, want 'hello world'", content)
	}
}

func TestDownload(t *testing.T) {
	downloadDir := t.TempDir()
	os.WriteFile(filepath.Join(downloadDir, "data.bin"), []byte("binary content"), 0644)

	handler := transfer.NewHandler(downloadDir, 10*1024*1024)

	req := httptest.NewRequest(http.MethodGet, "/api/download?file=data.bin", nil)
	w := httptest.NewRecorder()

	handler.Download(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("status = %d", w.Code)
	}

	body, _ := io.ReadAll(w.Body)
	if string(body) != "binary content" {
		t.Errorf("body = %q", body)
	}
}

func TestDownloadPathTraversal(t *testing.T) {
	handler := transfer.NewHandler(t.TempDir(), 10*1024*1024)

	req := httptest.NewRequest(http.MethodGet, "/api/download?file=../../../etc/passwd", nil)
	w := httptest.NewRecorder()

	handler.Download(w, req)

	if w.Code != http.StatusBadRequest {
		t.Errorf("path traversal not blocked: status = %d", w.Code)
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
go test ./internal/transfer/ -v
```

Expected: FAIL

- [ ] **Step 3: Implement upload.go**

Create `internal/transfer/upload.go`:
```go
package transfer

import (
	"encoding/json"
	"io"
	"net/http"
	"os"
	"path/filepath"
)

type Handler struct {
	baseDir string
	maxSize int64
}

func NewHandler(baseDir string, maxSize int64) *Handler {
	os.MkdirAll(baseDir, 0755)
	return &Handler{baseDir: baseDir, maxSize: maxSize}
}

func (h *Handler) Upload(w http.ResponseWriter, r *http.Request) {
	r.Body = http.MaxBytesReader(w, r.Body, h.maxSize)

	if err := r.ParseMultipartForm(h.maxSize); err != nil {
		http.Error(w, "file too large", http.StatusBadRequest)
		return
	}

	file, header, err := r.FormFile("file")
	if err != nil {
		http.Error(w, "no file provided", http.StatusBadRequest)
		return
	}
	defer file.Close()

	filename := filepath.Base(header.Filename)
	if filename == "." || filename == ".." {
		http.Error(w, "invalid filename", http.StatusBadRequest)
		return
	}

	destPath := filepath.Join(h.baseDir, filename)
	dest, err := os.Create(destPath)
	if err != nil {
		http.Error(w, "failed to create file", http.StatusInternalServerError)
		return
	}
	defer dest.Close()

	written, err := io.Copy(dest, file)
	if err != nil {
		http.Error(w, "failed to write file", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"filename": filename,
		"size":     written,
	})
}
```

- [ ] **Step 4: Implement download.go**

Create `internal/transfer/download.go`:
```go
package transfer

import (
	"net/http"
	"os"
	"path/filepath"
	"strings"
)

func (h *Handler) Download(w http.ResponseWriter, r *http.Request) {
	filename := r.URL.Query().Get("file")
	if filename == "" {
		http.Error(w, "file parameter required", http.StatusBadRequest)
		return
	}

	// Prevent path traversal
	cleaned := filepath.Clean(filename)
	if strings.Contains(cleaned, "..") || filepath.IsAbs(cleaned) {
		http.Error(w, "invalid file path", http.StatusBadRequest)
		return
	}

	fullPath := filepath.Join(h.baseDir, cleaned)

	// Verify the resolved path is within baseDir
	absBase, _ := filepath.Abs(h.baseDir)
	absPath, _ := filepath.Abs(fullPath)
	if !strings.HasPrefix(absPath, absBase) {
		http.Error(w, "invalid file path", http.StatusBadRequest)
		return
	}

	info, err := os.Stat(fullPath)
	if err != nil {
		http.Error(w, "file not found", http.StatusNotFound)
		return
	}

	w.Header().Set("Content-Disposition", "attachment; filename=\""+filepath.Base(cleaned)+"\"")
	w.Header().Set("Content-Type", "application/octet-stream")

	http.ServeFile(w, r, fullPath)
	_ = info
}
```

- [ ] **Step 5: Run tests**

```bash
go test ./internal/transfer/ -v
```

Expected: PASS

- [ ] **Step 6: Wire into server**

Add to `internal/server/server.go`:
```go
// In New():
if cfg.Recording.Dir != "" {
    transferHandler := transfer.NewHandler(cfg.Recording.Dir, 50*1024*1024)
    s.mux.HandleFunc("/api/upload", s.authMiddleware(transferHandler.Upload))
    s.mux.HandleFunc("/api/download", s.authMiddleware(transferHandler.Download))
}
```

- [ ] **Step 7: Commit**

```bash
git add internal/transfer/ internal/server/
git commit -m "feat: add file upload/download with path traversal protection"
```

---

## Phase 6: Session Recording

### Task 11: Asciicast v2 recorder

**Files:**
- Create: `internal/recording/recorder.go`
- Create: `internal/recording/player.go`
- Create: `internal/recording/recorder_test.go`

- [ ] **Step 1: Write the failing test**

Create `internal/recording/recorder_test.go`:
```go
package recording_test

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/valorisa/ShellFromBrowser/internal/recording"
)

func TestRecorder(t *testing.T) {
	dir := t.TempDir()
	rec, err := recording.New(dir, "test-session", 80, 24)
	if err != nil {
		t.Fatalf("New: %v", err)
	}

	rec.Write([]byte("hello "))
	time.Sleep(10 * time.Millisecond)
	rec.Write([]byte("world\r\n"))
	rec.Close()

	// Read the cast file
	path := filepath.Join(dir, "test-session.cast")
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("ReadFile: %v", err)
	}

	lines := strings.Split(strings.TrimSpace(string(data)), "\n")
	if len(lines) < 3 {
		t.Fatalf("expected at least 3 lines (header + 2 events), got %d", len(lines))
	}

	// Check header
	var header map[string]interface{}
	json.Unmarshal([]byte(lines[0]), &header)
	if header["version"] != float64(2) {
		t.Errorf("version = %v, want 2", header["version"])
	}
	if header["width"] != float64(80) {
		t.Errorf("width = %v, want 80", header["width"])
	}
}

func TestRecorderListCasts(t *testing.T) {
	dir := t.TempDir()

	rec1, _ := recording.New(dir, "sess1", 80, 24)
	rec1.Write([]byte("data"))
	rec1.Close()

	rec2, _ := recording.New(dir, "sess2", 120, 40)
	rec2.Write([]byte("data"))
	rec2.Close()

	casts, err := recording.List(dir)
	if err != nil {
		t.Fatalf("List: %v", err)
	}
	if len(casts) != 2 {
		t.Errorf("len = %d, want 2", len(casts))
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
go test ./internal/recording/ -v
```

Expected: FAIL

- [ ] **Step 3: Implement recorder.go**

Create `internal/recording/recorder.go`:
```go
package recording

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"
)

type header struct {
	Version   int    `json:"version"`
	Width     int    `json:"width"`
	Height    int    `json:"height"`
	Timestamp int64  `json:"timestamp"`
	Title     string `json:"title,omitempty"`
}

type Recorder struct {
	file      *os.File
	startTime time.Time
	mu        sync.Mutex
}

func New(dir, sessionID string, cols, rows int) (*Recorder, error) {
	os.MkdirAll(dir, 0755)
	path := filepath.Join(dir, sessionID+".cast")
	file, err := os.Create(path)
	if err != nil {
		return nil, err
	}

	h := header{
		Version:   2,
		Width:     cols,
		Height:    rows,
		Timestamp: time.Now().Unix(),
	}
	headerJSON, _ := json.Marshal(h)
	file.Write(headerJSON)
	file.Write([]byte("\n"))

	return &Recorder{
		file:      file,
		startTime: time.Now(),
	}, nil
}

func (r *Recorder) Write(data []byte) {
	r.mu.Lock()
	defer r.mu.Unlock()

	elapsed := time.Since(r.startTime).Seconds()
	escaped, _ := json.Marshal(string(data))
	line := fmt.Sprintf("[%.6f, \"o\", %s]\n", elapsed, escaped)
	r.file.WriteString(line)
}

func (r *Recorder) Close() error {
	r.mu.Lock()
	defer r.mu.Unlock()
	return r.file.Close()
}

type CastInfo struct {
	ID        string    `json:"id"`
	Filename  string    `json:"filename"`
	Width     int       `json:"width"`
	Height    int       `json:"height"`
	Timestamp time.Time `json:"timestamp"`
	Size      int64     `json:"size"`
}

func List(dir string) ([]CastInfo, error) {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return nil, err
	}

	var casts []CastInfo
	for _, entry := range entries {
		if entry.IsDir() || !strings.HasSuffix(entry.Name(), ".cast") {
			continue
		}

		info, _ := entry.Info()
		path := filepath.Join(dir, entry.Name())
		data, err := os.ReadFile(path)
		if err != nil {
			continue
		}

		lines := strings.SplitN(string(data), "\n", 2)
		if len(lines) == 0 {
			continue
		}

		var h header
		json.Unmarshal([]byte(lines[0]), &h)

		id := strings.TrimSuffix(entry.Name(), ".cast")
		casts = append(casts, CastInfo{
			ID:        id,
			Filename:  entry.Name(),
			Width:     h.Width,
			Height:    h.Height,
			Timestamp: time.Unix(h.Timestamp, 0),
			Size:      info.Size(),
		})
	}
	return casts, nil
}
```

- [ ] **Step 4: Implement player.go**

Create `internal/recording/player.go`:
```go
package recording

import (
	"encoding/json"
	"net/http"
	"os"
	"path/filepath"
	"strings"
)

type Player struct {
	dir string
}

func NewPlayer(dir string) *Player {
	return &Player{dir: dir}
}

func (p *Player) HandleList(w http.ResponseWriter, r *http.Request) {
	casts, err := List(p.dir)
	if err != nil {
		http.Error(w, "failed to list recordings", http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(casts)
}

func (p *Player) HandleGet(w http.ResponseWriter, r *http.Request) {
	id := r.URL.Query().Get("id")
	if id == "" || strings.Contains(id, "..") || strings.Contains(id, "/") {
		http.Error(w, "invalid id", http.StatusBadRequest)
		return
	}

	path := filepath.Join(p.dir, id+".cast")
	data, err := os.ReadFile(path)
	if err != nil {
		http.Error(w, "recording not found", http.StatusNotFound)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.Write(data)
}
```

- [ ] **Step 5: Run tests**

```bash
go test ./internal/recording/ -v
```

Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add internal/recording/
git commit -m "feat: add session recording in asciicast v2 format with playback"
```

---

## Phase 7: Docker + Deployment

### Task 12: Dockerfile and docker-compose

**Files:**
- Create: `Dockerfile`
- Create: `docker-compose.yml`
- Create: `.dockerignore`

- [ ] **Step 1: Create Dockerfile**

Create `Dockerfile`:
```dockerfile
# Build stage
FROM golang:1.22-alpine AS builder

RUN apk add --no-cache git

WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download

COPY . .
RUN CGO_ENABLED=0 go build -ldflags "-s -w -X main.version=$(git describe --tags --always) -X main.commit=$(git rev-parse --short HEAD)" -o /bin/shellfb ./cmd/shellfb

# Runtime stage
FROM alpine:3.19

RUN apk add --no-cache \
    bash \
    openssh-client \
    ca-certificates \
    && adduser -D -h /home/shellfb shellfb

COPY --from=builder /bin/shellfb /usr/local/bin/shellfb
COPY config.example.yaml /etc/shellfb/config.yaml

USER shellfb
WORKDIR /home/shellfb

EXPOSE 8080

ENTRYPOINT ["shellfb"]
CMD ["--config", "/etc/shellfb/config.yaml"]
```

- [ ] **Step 2: Create .dockerignore**

Create `.dockerignore`:
```
bin/
*.exe
.git/
.gitignore
*.md
recordings/
```

- [ ] **Step 3: Create docker-compose.yml**

Create `docker-compose.yml`:
```yaml
services:
  shellfb:
    build: .
    image: shellfb:latest
    container_name: shellfb
    ports:
      - "8080:8080"
    volumes:
      - ./config.yaml:/etc/shellfb/config.yaml:ro
      - shellfb-recordings:/home/shellfb/recordings
    environment:
      - SHELLFB_ADDR=:8080
    restart: unless-stopped

volumes:
  shellfb-recordings:
```

- [ ] **Step 4: Test Docker build**

```bash
cd ShellFromBrowser
docker build -t shellfb:dev .
```

Expected: builds successfully.

- [ ] **Step 5: Commit**

```bash
git add Dockerfile docker-compose.yml .dockerignore
git commit -m "feat: add Dockerfile (multi-stage) and docker-compose"
```

---

## Phase 8: Polish, Security, Documentation

### Task 13: Security hardening

**Files:**
- Modify: `internal/server/server.go`
- Create: `internal/server/middleware.go`

- [ ] **Step 1: Create security middleware**

Create `internal/server/middleware.go`:
```go
package server

import (
	"net/http"
	"time"
)

func securityHeaders(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("X-Content-Type-Options", "nosniff")
		w.Header().Set("X-Frame-Options", "DENY")
		w.Header().Set("X-XSS-Protection", "1; mode=block")
		w.Header().Set("Referrer-Policy", "no-referrer")
		w.Header().Set("Content-Security-Policy",
			"default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; connect-src 'self' ws: wss:")
		next.ServeHTTP(w, r)
	})
}

type rateLimiter struct {
	requests map[string][]time.Time
	max      int
	window   time.Duration
}

func newRateLimiter(max int, window time.Duration) *rateLimiter {
	return &rateLimiter{
		requests: make(map[string][]time.Time),
		max:      max,
		window:   window,
	}
}

func (rl *rateLimiter) Allow(ip string) bool {
	now := time.Now()
	cutoff := now.Add(-rl.window)

	// Clean old entries
	var valid []time.Time
	for _, t := range rl.requests[ip] {
		if t.After(cutoff) {
			valid = append(valid, t)
		}
	}

	if len(valid) >= rl.max {
		rl.requests[ip] = valid
		return false
	}

	rl.requests[ip] = append(valid, now)
	return true
}

func (rl *rateLimiter) Middleware(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		ip := r.RemoteAddr
		if fwd := r.Header.Get("X-Forwarded-For"); fwd != "" {
			ip = fwd
		}
		if !rl.Allow(ip) {
			http.Error(w, "rate limit exceeded", http.StatusTooManyRequests)
			return
		}
		next(w, r)
	}
}
```

- [ ] **Step 2: Apply middleware in server.go**

In `New()`, wrap the mux:
```go
func (s *Server) Handler() http.Handler {
	return securityHeaders(s.mux)
}
```

Apply rate limiter to login:
```go
loginLimiter := newRateLimiter(5, time.Minute)
s.mux.HandleFunc("/api/login", loginLimiter.Middleware(s.handleLogin))
```

- [ ] **Step 3: Commit**

```bash
git add internal/server/middleware.go internal/server/server.go
git commit -m "feat: add security headers, CSP, and rate limiting on login"
```

---

### Task 14: README and LICENSE

**Files:**
- Create: `README.md`
- Create: `LICENSE`

- [ ] **Step 1: Create README**

Create `README.md`:
```markdown
# ShellFromBrowser

A modern, cross-platform web-based terminal emulator written in Go. Spiritual successor to ShellInBox with SSH client support, multi-sessions, file transfer, and session recording.

## Features

- **Browser-based terminal** — Full xterm.js terminal emulation (256 colors, Unicode, mouse)
- **Multi-session tabs** — Multiple terminal sessions in one browser window
- **SSH client** — Connect to remote hosts directly from the browser
- **Authentication** — JWT-based auth with configurable user backends
- **TLS/HTTPS** — Built-in TLS support
- **File transfer** — Upload/download files through the web interface
- **Session recording** — Record and replay sessions (asciicast v2 format)
- **Cross-platform** — Runs on Linux, macOS, Windows
- **Single binary** — Zero runtime dependencies, embed everything
- **Docker ready** — Multi-stage Dockerfile included

## Quick Start

### Binary

```bash
# Download from releases or build from source
go install github.com/valorisa/ShellFromBrowser/cmd/shellfb@latest

# Run with defaults (no auth, port 8080)
shellfb

# Run with config
shellfb --config config.yaml
```

### Docker

```bash
docker compose up -d
```

Open http://localhost:8080

## Configuration

Copy `config.example.yaml` and customize:

```yaml
server:
  addr: ":8080"
  tls:
    enabled: true
    cert: "/path/to/cert.pem"
    key: "/path/to/key.pem"

auth:
  enabled: true
  jwt_secret: "your-secret-here"
  users:
    - username: admin
      password_hash: "$2a$10$..."

ssh:
  enabled: true

recording:
  enabled: true
  dir: "./recordings"
```

### Generate password hash

```bash
shellfb hash-password
```

## Build from source

```bash
git clone https://github.com/valorisa/ShellFromBrowser.git
cd ShellFromBrowser
make build
./bin/shellfb
```

## Security

- All WebSocket connections require authentication when auth is enabled
- JWT tokens with configurable expiry
- Rate limiting on login endpoint
- Security headers (CSP, X-Frame-Options, etc.)
- Path traversal protection on file operations
- No eval(), no inline scripts

## License

MIT
```

- [ ] **Step 2: Create LICENSE (MIT)**

Create `LICENSE`:
```
MIT License

Copyright (c) 2026 valorisa

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

- [ ] **Step 3: Create .gitignore**

Create `.gitignore`:
```
bin/
*.exe
recordings/
config.yaml
.env
```

- [ ] **Step 4: Commit**

```bash
git add README.md LICENSE .gitignore
git commit -m "docs: add README, LICENSE (MIT), and .gitignore"
```

---

### Task 15: hash-password CLI subcommand

**Files:**
- Modify: `cmd/shellfb/main.go`

- [ ] **Step 1: Add hash-password command**

Add to `cmd/shellfb/main.go` before the server startup logic:
```go
if len(os.Args) > 1 && os.Args[1] == "hash-password" {
    fmt.Print("Password: ")
    var password string
    fmt.Scanln(&password)
    hash, err := auth.HashPassword(password)
    if err != nil {
        log.Fatalf("hash: %v", err)
    }
    fmt.Println(hash)
    os.Exit(0)
}
```

Add import: `"github.com/valorisa/ShellFromBrowser/internal/auth"`

- [ ] **Step 2: Test it**

```bash
echo "test123" | go run ./cmd/shellfb hash-password
```

Expected: outputs a bcrypt hash starting with `$2a$`

- [ ] **Step 3: Commit**

```bash
git add cmd/shellfb/main.go
git commit -m "feat: add hash-password CLI subcommand"
```

---

### Task 16: GitHub repository setup

- [ ] **Step 1: Initialize git and push**

```bash
cd ShellFromBrowser
gh repo create valorisa/ShellFromBrowser --public --description "Modern web-based terminal emulator in Go — successor to ShellInBox" --source=. --push
```

- [ ] **Step 2: Add GitHub Actions CI**

Create `.github/workflows/ci.yml`:
```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  test:
    runs-on: ${{ matrix.os }}
    strategy:
      matrix:
        os: [ubuntu-latest, macos-latest, windows-latest]
        go: ['1.22']
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-go@v5
        with:
          go-version: ${{ matrix.go }}
      - run: go test ./... -race -v

  build:
    runs-on: ubuntu-latest
    needs: test
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-go@v5
        with:
          go-version: '1.22'
      - run: |
          GOOS=linux GOARCH=amd64 go build -o bin/shellfb-linux-amd64 ./cmd/shellfb
          GOOS=darwin GOARCH=arm64 go build -o bin/shellfb-darwin-arm64 ./cmd/shellfb
          GOOS=windows GOARCH=amd64 go build -o bin/shellfb-windows-amd64.exe ./cmd/shellfb
      - uses: actions/upload-artifact@v4
        with:
          name: binaries
          path: bin/
```

- [ ] **Step 3: Commit and push**

```bash
git add .github/
git commit -m "ci: add GitHub Actions workflow for test and cross-platform build"
git push
```

---

## Summary of Phases

| Phase | Tasks | Delivers |
|-------|-------|----------|
| 1 — Scaffold + Basic Terminal | 1-4 | Working terminal in browser (local shell) |
| 2 — Auth + TLS | 5-6 | Login screen, JWT auth, YAML config |
| 3 — Multi-Sessions | 7-8 | Tab UI, session manager, reconnection |
| 4 — SSH Client | 9 | Connect to remote hosts via browser |
| 5 — File Transfer | 10 | Upload/download files |
| 6 — Recording | 11 | Session recording + playback |
| 7 — Docker | 12 | Dockerfile + compose |
| 8 — Polish | 13-16 | Security, docs, CI, GitHub |

Each phase produces a working, testable binary. Phase 1 alone gives you a functional terminal in the browser.
