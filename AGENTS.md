# Repository Guidelines

## Project Structure & Module Organization

- `src/`: Go server, authoritative simulation, WebSocket transport, rooms, matchmaking, and adjacent `*_test.go` files; one `leqra` module using `package main`.
- `src/web/`: `index.html` and the versioned browser assets under `assets/v<version>/`. `src/tests/` contains JavaScript tests and optional browser/protocol harnesses.
- `tests/`: mocked deployment tests. `scripts/`: optional asset-generation utilities. `deploy/`: deployment script, service, and environment settings. `docs/`: player guides, protocol, and release notes.

## Build, Test, and Development Commands

Run from the repository root. Use Go 1.23+, Node.js for JavaScript tests, and Python 3 for deployment tests.

- `go run ./src` or `./dev.sh`: start locally at `http://localhost:8080`.
- `go build -trimpath -o bin/leqra ./src`: build the executable with embedded assets.
- `go test -race -count=1 ./...`: run Go tests with race detection.
- `node --test src/tests/*.test.cjs`: run Node's built-in test suite.
- `python3 -m unittest discover -s tests -p 'test_deploy.py' -v`: run deployment tests without contacting a host.
- `go vet ./...`, `node --check src/web/assets/v*/game.js`, and `sh -n deploy/ensure.sh`: run static checks.

## Coding Style & Naming Conventions

Format Go with `gofmt`; use tabs, exported `CamelCase`, and unexported `camelCase` identifiers. Prefer descriptive snake_case filenames. Preserve surrounding compact JavaScript/CSS formatting and use JavaScript `camelCase`. Python uses four-space indentation. Avoid unrelated reformatting and preserve existing staged and unstaged edits.

Get the user's approval before editing the root `README.md`.

Leave letter spacing at its default in CSS.

## Testing Guidelines

Add deterministic regressions for bugs. Name Go tests `TestBehavior` in `*_test.go`; place Node tests in `src/tests/*.test.cjs`. Keep shared gameplay behavior consistent between Go and JavaScript, using parity fixtures where applicable. Benchmark performance claims. Run focused tests first, then relevant full suites. No numeric coverage threshold is configured. Historical browser results are not current verification; record skipped browser/device checks.

Keep generated test results out of version control, including logs, benchmark output, and test screenshots.

## Assets & Configuration

Keep `index.html` at the web root and all other browser files in the current versioned asset directory. Align server/client versions, HTML references, and PWA cache paths. Rebuild after asset changes. Configure locally through `PORT`, `ADDR`, `MAX_ROOMS`, and `ALLOWED_ORIGINS`. `deploy/ensure.sh` performs real remote deployment and restarts the service.

## Commit & Pull Request Guidelines

History primarily uses release subjects such as `v4.45.1` and short descriptions; no Conventional Commits scheme is enforced. Use concise, descriptive summaries. PRs should explain behavior changes, link relevant issues, list validation, and include screenshots for visible UI changes.
