# leqra v4.23.2 test notes

## New v4.23.2 regressions

`tests/polish4232_browser.py` passed **8/8** checks:

- a fresh 390×844 touch/mobile profile starts with Compact 7×7;
- a previously saved Large maze choice remains Large on the same mobile profile;
- C fires Player 1 with one local pilot;
- Enter fires Player 1 with one local pilot;
- C fires Player 1 only when local Player 2 is active;
- Enter fires Player 2 only when local Player 2 is active;
- Controls help displays the supplemental C/Enter bindings;
- no uncaught browser errors occurred.

## Retained verification

The final source also passed:

- `node --test tests/*.test.cjs` — **57/57**;
- `go test -race -count=1 ./...` — passed;
- `go vet ./...` — passed;
- `go build -trimpath` — passed;
- JavaScript syntax checks for the shipped game/netcode/theme/PWA/service-worker assets — passed;
- retained v4.23 browser/PWA/online regression — **18/18**;
- retained desktop gameplay/HUD regression — **16/16**;
- retained narrow-mobile regression — **6/6**;
- branding/storage migration — **12/12**;
- results/layout/browser regression — **8/8**;
- Safari/WebKit identity-path regression — **26/26**.

The old `tests/polish46_browser.py` is a historical v4.6 script that intentionally hard-codes `leqra.version === '4.6.0'`; it is not a current-release runner. Its modern successor coverage above passes.

Browser checks use Chromium and emulated device/browser identities. Physical iPhone/Android hardware and native Safari were not exercised in this container.
