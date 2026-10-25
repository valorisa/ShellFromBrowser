# Contributing to ShellFromBrowser

Thank you for considering contributing to ShellFromBrowser! We welcome contributions from the community.

## How to Contribute

### Reporting Issues

- Check if the issue has already been reported in [Issues](https://github.com/valorisa/ShellFromBrowser/issues)
- Use a clear and descriptive title
- Provide steps to reproduce the problem
- Include your environment details (OS, Go version, browser)
- Add relevant logs or screenshots if applicable

### Suggesting Features

- Open an issue with the `enhancement` label
- Describe the feature and its use case
- Explain why this feature would be useful to most users

### Pull Request Workflow

1. **Fork the repository**
   ```bash
   gh repo fork valorisa/ShellFromBrowser --clone
   cd ShellFromBrowser
   ```

2. **Create a feature branch**
   ```bash
   git checkout -b feature/your-feature-name
   ```

3. **Make your changes**
   - Follow the coding conventions below
   - Write or update tests as needed
   - Update documentation if required

4. **Test your changes**
   ```bash
   make test
   ```

5. **Format your code**
   ```bash
   gofmt -w .
   ```

6. **Commit your changes**
   - Use clear and descriptive commit messages
   - Follow the [Conventional Commits](https://www.conventionalcommits.org/) format:
     - `feat:` for new features
     - `fix:` for bug fixes
     - `docs:` for documentation changes
     - `refactor:` for code refactoring
     - `test:` for test additions or modifications
     - `chore:` for maintenance tasks

7. **Push to your fork**
   ```bash
   git push origin feature/your-feature-name
   ```

8. **Open a Pull Request**
   - Provide a clear description of the changes
   - Reference any related issues
   - Ensure CI checks pass

## Coding Conventions

### Go Style

- Follow the [Effective Go](https://golang.org/doc/effective_go.html) guidelines
- Use `gofmt` to format all Go code
- Run `go vet` to catch common mistakes
- Use meaningful variable and function names
- Add comments for exported functions and types
- Keep functions focused and concise

### Code Organization

- Place new features in appropriate packages under `internal/`
- Keep frontend code in `web/static/`
- Update relevant documentation in `docs/` if needed

### Testing

- Write unit tests for new functionality
- Ensure existing tests pass: `make test`
- Aim for meaningful test coverage
- Use table-driven tests where appropriate

### Commit Messages

Good commit messages help maintain a clear project history:

```
feat: add support for SSH key authentication

- Parse private key files in SSH client
- Add key parameter to WebSocket endpoint
- Update documentation with key usage examples

Closes #42
```

## Development Setup

### Prerequisites

- Go 1.27.3 or later
- Git
- Make (optional, but recommended)

### Building from Source

```bash
git clone https://github.com/valorisa/ShellFromBrowser.git
cd ShellFromBrowser

# Build the binary
make build

# Run tests
make test

# Run the application
./bin/shellfb
```

### Project Structure

```
cmd/shellfb/          # Application entry point
internal/             # Internal packages (not importable)
  auth/               # Authentication logic
  config/             # Configuration handling
  recording/          # Session recording
  server/             # HTTP/WebSocket server
  ssh/                # SSH client
  terminal/           # PTY management
  transfer/           # File transfer
web/static/           # Frontend assets (embedded)
```

## Code Review Process

- All submissions require review
- Maintainers may request changes or improvements
- Be responsive to feedback and questions
- Once approved, a maintainer will merge your PR

## Community Guidelines

- Be respectful and constructive
- Follow the [Code of Conduct](CODE_OF_CONDUCT.md)
- Help others when you can
- Ask questions if something is unclear

## License

By contributing, you agree that your contributions will be licensed under the [MIT License](LICENSE).

---

**Thank you for contributing to ShellFromBrowser!**
