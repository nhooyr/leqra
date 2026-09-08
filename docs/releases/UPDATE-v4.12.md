# leqra v4.12 — cleaner combat HUD and larger remote power badges

## Changes

- Removed the fire-key badge from the under-arena loadout HUD entirely. Keyboard controls remain in the Field Manual and Controls menu. The offline latency/score placeholder also starts empty, so no duplicate `FIRST TO 5` text flashes during boot.
- Local in-game menus no longer show the obsolete **Return to room to share online** action. Online rooms still show **Copy invite link** normally.
- The built-in **8-tank Free-for-all** preset now uses the **Giant 16×14** maze. The 4-tank FFA preset remains Large 12×10.
- Active power-up badges on bots and remote online tanks are now **2× the previous display size**. They remain cached and begin at the top-right of the tank, continuing clockwise for additional effects.

No weapon balance, physics, scoring, matchmaking, spectator, chat, or networking behavior changed in this release.

## Install

Replace all Go sources and the complete `web/` folder, then restart:

```sh
cd leqra-online
go run .
```

Refresh all players and spectators. Rebuild compiled/Docker deployments because the Go executable embeds the browser assets. Both `/healthz` and `leqra.version` report **4.12.0**.

## Verification

The final source passed the full Go test suite under the race detector, all **56** JavaScript networking/prediction tests, `go vet`, JavaScript syntax validation, and a compiled-server build. A focused Chromium test at 320×568 also verified all four requested changes with no uncaught browser errors.
