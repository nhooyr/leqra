# leqra v4.13 test notes

## Focused layout check

The normal desktop shell was compared with the existing fullscreen layout class using the exact shipped HTML/CSS in headless Chromium. Viewports checked: **800×700, 1024×768, 1365×950, and 1920×1080**.

At every viewport, the measured bounding rectangles for the **header, main grid, and arena shell changed by 0 px in x, y, width, and height** when the fullscreen class was toggled. The desktop hero and footer were already hidden before fullscreen, and the old desktop status slogan was absent.

This isolates the CSS/layout transition itself. Browser chrome behavior and physical-monitor fullscreen behavior can still vary by browser/OS. Touch/mobile styles are not changed by this patch.

## Regression/build checks

- `go test -race ./...` — passed.
- `node --test tests/*.test.cjs` — **56/56 passed**.
- `go vet ./...` — passed.
- `node --check web/game.js` — passed.
- `go build -trimpath` — passed.
