# leqra v4.13 — compact desktop shell

The normal desktop page now uses the same compact shell geometry that fullscreen mode already used. The large hero banner and footer are hidden on desktop, the header uses compact padding, the old desktop status slogan is removed, and the app can use the full viewport width and height.

This gives the maze more room before fullscreen and dramatically reduces the visual shift when entering or leaving fullscreen. The sidebar remains available unless the user hides it with the existing sidebar control. Touch/mobile layouts are unchanged.

## Install

Replace all Go sources and the complete `web/` directory, then restart:

```sh
cd leqra-online
go run .
```

Refresh players and spectators. Rebuild compiled or Docker deployments because the browser assets are embedded. `/healthz` and `leqra.version` report **4.13.0**.
