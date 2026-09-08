# leqra v4.25.0 — bug fixes and performance

## Fixed

- Custom key bindings now take priority over supplemental C/Enter fire shortcuts. A key assigned to movement or another pilot no longer fires an unintended tank. Control summaries and the field manual show only available aliases and avoid duplicate fire labels.
- Renaming an online room A → B → A no longer makes a token reconnect recurse indefinitely. Reconnecting through the current or intermediate name resolves the correct room directly.
- A disconnected player's earlier rematch vote no longer starts a rematch without that player. Disconnection clears their vote, and every required controller must have a live socket before restart.
- Clinching a match freezes its winner, participants, statistics and scores immediately, while retaining the existing 2.7-second result delay. Spectating, swapping, leaving, rejoining or returning to a matchmaking party during that delay cannot erase a victory or give it to a replacement tank. Results use stable membership rather than reusable seat numbers. A restart action during a clinched local result opens the completed result.
- Bots stop immediately if their own remotely detonated grenade kills them. They no longer move their destroyed tank after the blast. The correction applies to both local JavaScript and Go simulation.
- Room updates preserve unchanged roster controls and unfinished bot-name edits. Readiness and connection labels update without replacing the controls. Changed participants, replaced seats and changed permissions still rebuild the affected rows.

## Optimized

- Go bot pathfinding uses a reusable indexed heap instead of repeatedly scanning every maze cell. It preserves route costs and exact tie-breaking. Seeded parity tests compare it with the former algorithm.
- Room metadata is JSON-encoded once per broadcast and the immutable bytes are shared among recipients, instead of encoding the same message separately for every connected player and spectator.
- Roster rendering updates only affected rows, avoiding repeated control creation and DOM attachment. The ordinary roster and moderation roster have independent bounded caches.

In isolated measurements on this environment, ultrawide 24×14 bot route planning improved from a median 117.2 µs to 6.45 µs (about 18× faster, zero allocations after warm-up). A full-gallery room broadcast improved from about 2.04 ms to 108 µs (about 19× faster), with allocated memory falling from about 779 KB to 64 KB. These are operation-specific benchmarks, not overall FPS, latency or server-capacity claims. See `TEST-NOTES-v4.25.0.md` and `tests/results/v4.25.0/`.

## Upgrade

Replace the Go sources and the complete `web/` directory, then rebuild and restart:

```sh
cd leqra-online
go build -trimpath -o leqra .
./leqra
```

Go 1.23 or newer is required. The Go version, browser version and service-worker cache now agree on **4.25.0**. All served static assets use `/assets/v4.25.0/` to avoid stale immutable caches. Offline local play, PWA installation, four-team assignment and two-team CTF remain supported.

Gameplay/UI ideas are in `IMPROVEMENTS-v4.25.0.md`; they are suggestions and have not been added as new features.
