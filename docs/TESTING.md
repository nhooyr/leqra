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

Keep generated reports and screenshots local. Older raw results are available in the repository history.

## Browser checks for the current release

The maintained Playwright harness opens `src/web/index.html` directly and checks the intro tour, keyboard controls, and mobile sidebar in desktop and touch layouts.

```sh
python3 -m pip install playwright
python3 -m playwright install chromium
python3 src/tests/intro_tour_browser.py
```

For live checks, run `go run ./src` and open the served page in separate browser contexts. Check a shared match and verify that the service worker can reload the app offline after installation.

## Historical harnesses

The other Python browser and protocol scripts in `src/tests/`, including `browser_smoke.py` and `protocol_smoke.py`, are release-specific. Run them against their matching revision. Their assertions can cover retired behavior such as grenade self-damage. For historical scripts that request the opt-in Go fixture, start it from that revision.

```sh
LEQRA_BROWSER_FIXTURE=1 LEQRA_BROWSER_ADDR=127.0.0.1:18790 \
  go test -run '^TestBrowserFixture$' -timeout 30m ./src
```

[Historical verification reports](releases/)
