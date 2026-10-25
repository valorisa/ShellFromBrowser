# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.5.0] - 2026-10-25

### Added

- `.dockerignore` rules excluding local secrets and settings from the Docker build context
- `.gitignore` rules for local test certificates, test configuration and local Claude settings
- Planning documents (plans and specs) under `docs/superpowers/`

### Changed

- Minimum Go version raised to 1.27.3; README and CONTRIBUTING prerequisites updated accordingly
- Docker base images updated (builder `golang:1.27-alpine`, runtime `alpine:3.24`)
- CI workflow updated: newer GitHub Actions (setup-go v7, upload-artifact v7) and Go 1.27
- Dependencies: `golang.org/x/crypto` bumped from 0.51.0 to 0.58.0
- Network constraint diagram revised in the deployment documentation

## [0.1.0] - 2026-05-15

### Added

- Browser-based terminal emulator with xterm.js (256 colors, Unicode, mouse support)
- WebSocket server with bidirectional PTY communication
- Cross-platform PTY spawning (Unix via creack/pty, Windows via ConPTY/pipes)
- JWT authentication with bcrypt password hashing
- YAML configuration system with sensible defaults
- Multi-session support with tab-based UI
- Session manager with per-user limits
- SSH client integration for connecting to remote hosts
- File upload/download with path traversal protection
- Session recording in asciicast v2 format (asciinema-compatible)
- TLS/HTTPS built-in support
- Security headers (CSP, X-Frame-Options, X-Content-Type-Options)
- Rate limiting on login endpoint
- `hash-password` CLI subcommand for generating bcrypt hashes
- Multi-stage Dockerfile and docker-compose deployment
- GitHub Actions CI with cross-platform testing and binary builds
- Embedded static assets via go:embed (single binary distribution)

[Unreleased]: https://github.com/valorisa/ShellFromBrowser/compare/v0.5.0...HEAD
[0.5.0]: https://github.com/valorisa/ShellFromBrowser/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/valorisa/ShellFromBrowser/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/valorisa/ShellFromBrowser/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/valorisa/ShellFromBrowser/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/valorisa/ShellFromBrowser/releases/tag/v0.1.0
