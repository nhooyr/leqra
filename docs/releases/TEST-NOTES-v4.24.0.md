# leqra v4.24.0 verification

Completed against the updated source:

- `go test -race -count=1 -json ./...`: passed 484 top-level tests, 892 tests including subtests.
- `node --test tests/*.test.cjs`: 69 passed, 0 failed.
- `go vet ./...`: passed.
- `go build -trimpath`: passed using Go 1.23.12.
- All shipped JavaScript assets passed `node --check`.
- Versioned HTML entrypoints resolve to packaged files. Root JavaScript/CSS developer copies match their production asset copies byte for byte.
- `git diff --check`: passed.

The new Go regressions cover all eight seats, bots/local P2, new online guests, spectator entry, empty teams, FFA, CTF transitions, manual-assignment preservation, readiness resets, server rejection of invalid CTF teams, and legacy CTF preset/publish migration. Existing Go transport, simulation, PWA/cache, handshake and shutdown tests also pass.

The 12 new Node tests execute the shipped game functions with UI/network fixtures. They cover assignment through eight tanks, CTF dropdown contents, local/online edit validation, preset migration, spectators, pause visibility/labels, contextual rules fields, preservation of hidden settings, blocked active-match adds, and avoiding redundant field-manual DOM writes. Twenty unchanged room-summary updates write the field manual once; changed instructions trigger a new write.

Three prior assertions/fixtures were updated to match the requested behavior: four-team activation, CTF restricted to Teams 1/2, and test helpers that explicitly configure a desired team after adding a tank. Release-version assertions were advanced to 4.24.0.

Browser automation and physical iPhone/Android/Safari testing were not run for this release. Historical screenshot/browser results in `tests/results/` belong to the versions shown in those folders. Retained browser scripts have current version expectations, but their presence is not a claim of a new browser test pass.
