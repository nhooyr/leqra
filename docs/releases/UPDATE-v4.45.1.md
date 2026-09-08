# leqra v4.45.1

## Changes

- **Safer, faster deployment.** The deployment script builds into a temporary directory before contacting the host, preserves any existing local binary, repairs required remote directories on every run, uses two SSH sessions instead of many, reloads systemd after transferring the unit, and prevents failed builds or uploads from restarting the service.
- **Reliable offline caching.** The service worker clones successful responses before returning them, extends the fetch event through cache writes, tolerates Cache Storage read/write failures, and avoids caching HTTP error responses.
- **Lower idle server cost.** Rooms retained during reconnect grace no longer encode snapshots 30 times per second when no live player or spectator socket can receive them. Reconnecting players and spectators still receive the complete maze and subsequent state updates.

## Apply

Replace the server sources and complete browser assets, rebuild, restart, and refresh clients. From the repository root:

```sh
go build -trimpath -o bin/leqra ./src
./bin/leqra
```

Server, browser, PWA registration, and offline cache use 4.45.1.

See [TEST-NOTES-v4.45.1.md](TEST-NOTES-v4.45.1.md) for verification.
