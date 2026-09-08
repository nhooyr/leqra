# leqra v4.23.2 — mobile compact default and expanded fire controls

## Mobile starts Compact by default

A fresh mobile local room now selects **Compact (7×7)** as its default maze size. Desktop keeps the existing Large default. This is only a default: if the browser already has an explicitly saved local-room maze choice, that saved choice is preserved on mobile and desktop.

## More fire keys

The existing configurable fire bindings remain unchanged and the new keys are additional aliases:

- **Single player:** Q, Space, C, and Enter all fire/detonate for Player 1.
- **Two local players:** Player 1 uses Q or C; Player 2 uses Space or Enter.

The same ownership rule applies when a local Player 2 participates in an online room. Holding or tapping an alias goes through the normal fire state/press path, so grenade detonation and online input delivery use the same logic as the existing fire keys.

Control summaries and the Controls help panel now show these aliases.

## Upgrade

Replace the Go source and complete `web/` directory, then rebuild/restart. Browser assets are under `/assets/v4.23.2/`, so the versioned-asset system bypasses earlier cached JavaScript/CSS automatically.

```sh
go build -trimpath -o leqra .
./leqra
```

`/healthz`, `/api/config`, the browser API, and the Controls footer report **4.23.2**.
