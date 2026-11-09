# Testing leqra

Run from the repository root with Go 1.23+, Node.js, and Python 3.

```sh
go test -race -count=1 ./...
go vet ./...
go build -trimpath -o bin/leqra ./src
node --check src/web/assets/v*/game.js
node --test src/tests/*.test.cjs
python3 -m unittest discover -s tests -p 'test_deploy.py' -v
```

The Python suite exercises the deployment script with mocked builds, SSH, transfers, and remote commands.

For browser checks, start the local server and load the actual page. Check desktop and touch layouts, a match between two browser contexts, and offline startup through the service worker. For deterministic browser and protocol tests, the opt-in Go fixture is available locally.

```sh
LEQRA_BROWSER_FIXTURE=1 LEQRA_BROWSER_ADDR=127.0.0.1:18790 \
  go test -run '^TestBrowserFixture$' -timeout 30m ./src
```

Older harnesses in `src/tests/` may contain version-specific assertions. [Historical verification reports](releases/)
