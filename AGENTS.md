# Repository Guidelines

## Project Structure & Module Organization

- `src/`: Go server, authoritative simulation, WebSocket transport, rooms, matchmaking, and adjacent `*_test.go` files; one `leqra` module using `package main`.
- `src/web/`: browser game, styles, and HTML; `assets/v<version>/` holds production assets. `src/tests/` contains JavaScript tests, optional browser/protocol harnesses, and historical results.
- `tests/`: mocked deployment tests. `scripts/`: local launchers and utilities. `deploy/`: SSH deployment, systemd service, environment settings, and a Caddy example. `docs/`: development, protocol, and release guides.

## Build, Test, and Development Commands

Run from the repository root. Use Go 1.23+, Node.js for JavaScript tests, and Python 3 for deployment tests.

- `go run ./src`: start locally at `http://localhost:8080`; `sh scripts/run.sh` is the launcher equivalent.
- `go build -trimpath -o bin/leqra ./src`: build the executable with embedded assets.
- `go test -race -count=1 ./...`: run Go tests with race detection.
- `node --test src/tests/*.test.cjs`: run Node's built-in test suite.
- `python3 -m unittest discover -s tests -p 'test_deploy.py' -v`: run deployment tests without contacting a host.
- `go vet ./...`, `node --check src/web/game.js`, and `sh -n deploy/run.sh`: run static checks.

## Coding Style & Naming Conventions

Format Go with `gofmt`; use tabs, exported `CamelCase`, and unexported `camelCase` identifiers. Prefer descriptive snake_case filenames. Preserve surrounding compact JavaScript/CSS formatting and use JavaScript `camelCase`. Python uses four-space indentation. Avoid unrelated reformatting and preserve existing staged and unstaged edits.

## Testing Guidelines

Add deterministic regressions for bugs. Name Go tests `TestBehavior` in `*_test.go`; place Node tests in `src/tests/*.test.cjs`. Keep shared gameplay behavior consistent between Go and JavaScript, using parity fixtures where applicable. Benchmark performance claims. Run focused tests first, then relevant full suites. No numeric coverage threshold is configured. Historical browser results are not current verification; record skipped browser/device checks.

## Assets & Configuration

Keep existing unversioned source files and versioned production counterparts synchronized. Releases must align server/client versions, HTML references, and PWA cache paths. Rebuild after asset changes. Configure locally through `PORT`, `ADDR`, `MAX_ROOMS`, and `ALLOWED_ORIGINS`. `deploy/run.sh` performs real remote deployment and restarts the service.

## Commit & Pull Request Guidelines

History primarily uses release subjects such as `v4.45.1` and short descriptions; no Conventional Commits scheme is enforced. Use concise, descriptive summaries. PRs should explain behavior changes, link relevant issues, list validation, and include screenshots for visible UI changes.
