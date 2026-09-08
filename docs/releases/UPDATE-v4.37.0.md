# leqra v4.37.0

## Room controls

- Unshare Room and Leave Room now have distinct tinted backgrounds, borders, focus states and 44-pixel minimum touch targets. Unshare uses amber; Leave uses coral.
- The two actions share one row above Copy Invite Link, including on narrow layouts. When only Leave is available it spans the row.
- Join another room keeps its text-button styling and sits above Find Online Battle.
- Fixed Local P2's Remove button staying disabled after matchmaking was cancelled. Queue-only packets disabled cached roster controls without restoring them on cancellation. Adding/removing a bot accidentally unlocked them because cancelling a removal reset every button. Queue changes now refresh room controls, and cached removal buttons reconcile their current eligibility. Cancelling a confirmation respects queue, room, host and connection restrictions.

## Survival preview

The compact two-second result before a new wave shows only the completed wave and the time until the new maze. Boss difficulty and equipment appear only on the following three-second countdown, once the new wave is being initialized. The equipment reflects enabled rules. Pausing the local countdown shows Paused and resumes the same countdown afterward.

## Other bug fixes

- Online Rules and Presets wait for matching server-confirmed settings and, for presets, the expected roster. Unrelated readiness or name broadcasts cannot close the dialog as if Apply succeeded. Disconnects, rejection and timeout release pending controls while keeping the edited form.
- Invalid inherited object names in saved bot difficulties and power-up selections are rejected before they can reach bot tuning or preset application.
- Departed players keep the score they earned before their combat seat was cleared or reused, locally and online. Replacement participants retain their own scores; finalized reports stay frozen.
- CTF flags/bases and the King of the Hill objective remain visible through the compact final-result hold.

## Performance

Server room maintenance reuses one ordered roster snapshot per tick and stack storage for sorting spectators. It refreshes the snapshot after expiration because a departing controller can also remove local P2. Other callers still receive independent snapshots.

Five-run benchmark medians showed a full lobby tick decreasing from 4.050 to 2.325 microseconds (43% less time), and a parked private-room tick from 1.340 to 0.455 microseconds (66% less). Both full-roster tick cases eliminate four allocations, about 640 bytes per tick. These measure server maintenance operations, not game FPS or end-to-end latency. See `PERFORMANCE-v4.37.0.md` for fixtures and raw evidence.

## UI ideas awaiting approval

Broader menu restructuring has not been implemented. `UI-IDEAS-v4.37.0.md` describes three possible changes and their trade-offs.

## Install

Replace the Go sources and the complete `web/` folder, rebuild, and restart:

```sh
go build -trimpath -o leqra .
./leqra
```

Refresh clients after restarting. The server, browser, versioned assets and offline cache all use 4.37.0. See `TEST-NOTES-v4.37.0.md` for executed checks and remaining verification limits.
