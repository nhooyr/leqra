# leqra v4.24.0

## Teams and Capture the Flag

- Enabling Teams distributes active tanks evenly across Team 1–4, in seat order.
- Capture the Flag uses only Team 1 and Team 2. Entering CTF rebalances the roster across those two teams; leaving CTF for another team mode rebalances across four.
- Added bots, local Player 2, online guests and spectators entering play join the least-populated eligible team. Empty teams are eligible; ties use the lowest team number. Spectators do not count toward team sizes.
- The server makes the final assignment for new online tanks, so rapid or concurrent additions cannot rely on stale client counts.
- Hosts can still edit teams manually. Unrelated rules and roster edits preserve those assignments; adding a tank does not shuffle existing tanks.
- CTF dropdowns show only the first two teams, with custom team names. The server rejects unavailable team assignments. Old CTF imports/presets with other team numbers are automatically rebalanced into Team 1 and Team 2; valid preset assignments are retained.

## UI and fixes

- Pause is hidden on the home screen, in lobbies and at match completion. It remains available during countdowns, play, round transitions and local pause. Accessible labels distinguish Pause, Resume and the online Match menu.
- Rules hide team names/colours and friendly fire in Free-for-all, Teams 3/4 in CTF, and respawn delay in Elimination. Inactive values remain saved and unfinished hidden inputs cannot block submission.
- Removed obsolete colour-override instructions and repeated Free-for-all roster badges. The CTF/KOTH countdown now describes the actual objective.
- The new-bot difficulty control is disabled when all tank seats are filled. Local roster additions are guarded against active/locked matches, and spectator entry uses the same team policy as new tanks.
- Room updates no longer build the field manual twice, and unchanged content retains its DOM. Repeated online HUD labels use guarded text updates. These reduce avoidable DOM mutations; no universal FPS improvement is claimed.

## Upgrade

Replace the Go sources and the complete `web/` directory, then rebuild and restart:

```sh
cd leqra-online
go build -trimpath -o leqra .
./leqra
```

Go 1.23 or newer is required. All served browser assets now use `/assets/v4.24.0/`. The server version, browser version and service-worker shell agree. Offline local play, version checking, matchmaking, saved controls and the existing PWA workflow are retained.

See `TEST-NOTES-v4.24.0.md` for checks performed on this release.
