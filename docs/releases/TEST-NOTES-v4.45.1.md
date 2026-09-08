# leqra v4.45.1 verification

The release adds focused regressions for recipient-free server broadcasts, map delivery after player and spectator reconnects, service-worker cache timing and failure behavior, and deployment success/failure paths with all external commands mocked.

## Automated checks

Run from the repository root:

```sh
go test -race ./src

go vet ./src
go build -trimpath -o /tmp/leqra ./src
node --check src/web/netcode.js
node --check src/web/game.js
node --test src/tests/*.test.cjs
python3 -m unittest discover -s tests -p 'test_deploy.py' -v
```

The deployment tests do not contact a real host. Browser rendering, installation prompts, physical-device behavior, and a public deployment still require manual or environment-specific verification.
