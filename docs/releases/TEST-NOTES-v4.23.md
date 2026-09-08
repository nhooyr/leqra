# leqra v4.23 test notes

## Final verification summary

- Go race suite: **480 top-level tests run; 478 passed, 2 intentionally opt-in skips; 881 passing test/subtest events; 0 failures**
- JavaScript/Node suite: **57/57 passed**
- Go vet: **passed**
- JavaScript syntax checks: **theme.js, netcode.js and game.js passed**
- Compiled build: **passed**
- Focused v4.23 real-WebSocket injected-browser checks: **15/15 passed**
- Retained v4.22 focused browser checks: **9/9 passed**
- Retained v4.18 layout/results browser checks: **8/8 passed**
- Production SIGTERM/WebSocket smoke: **5/5 passed**

## v4.23 focused browser checks

`tests/polish423_browser.py` uses the opt-in loopback Go BrowserFixture and the exact shipped browser sources injected into Chromium. It passed these 15 assertions:

1. local startup opens no WebSocket;
2. local room exposes no New local room action;
3. a stale server hello asks the player to reload before online play;
4. version mismatch aborts online room setup;
5. Teams activation balances the default four tanks 2–2;
6. explicit Share Room Online opens exactly one WebSocket;
7. the online connection completes the v4.23 version handshake;
8. Unshare preserves the displayed maze;
9. focused chat suppresses gameplay controls;
10. visible but unfocused chat allows gameplay input;
11. refocusing chat suppresses gameplay input again;
12. online pause menu includes Leave match;
13. the test fixture queues the shutdown notice;
14. that notice returns the online client to local Home with visible shutdown copy;
15. no uncaught browser errors occur.

## Retained browser/network regression matrix

The final v4.23 source also passed **12/12** branding/storage migration checks, **16/16** desktop gameplay/HUD checks, **6/6** narrow-mobile layout/gameplay checks, **26/26** Safari/WebKit identity-path checks, **9/9** retained v4.22 room/chat/Ghost checks, **8/8** retained v4.18 results/layout checks, and **87/87** real-WebSocket matchmaking/browser checks. The 87-check run includes matchmaking queue formation, party consent, local P2, integrated chat privacy, spectators, reconnects, results/rematch, return-to-room, and no uncaught browser errors with the new v4.23 handshake in place.

## PWA and static-asset coverage

Go tests verify that `/` and `/index.html` serve the current HTML shell without an index redirect, the shell references `/assets/v4.23.0/...`, versioned assets receive immutable one-year cache headers, `/index.html` is revalidated, the service worker is allowed to control `/`, and legacy root asset URLs return 404. Source checks cover the manifest icons, offline shell list and network-only exclusions for WebSocket/API/health endpoints.

The build environment blocks direct Chromium navigation to loopback and `file:` URLs, so this run does **not** claim that a native iOS/Android install prompt was physically exercised. The installability contract is implemented, and physical iPhone/iPad Safari plus Android Chrome should be used for final device acceptance on an HTTPS deployment.

## Version and shutdown protocol coverage

Go tests require a real WebSocket client to send the matching `client_hello` before room commands are accepted. A stale v4.22 hello is rejected with `version_mismatch`; a matching v4.23.0/protocol-1 hello is accepted. The shutdown unit regression checks that the one encoded shutdown packet is queued for every connected client. A production-style SIGTERM smoke separately verifies that `server_shutdown` arrives on an actual WebSocket before teardown.

## Optimization notes

This pass intentionally avoids unmeasured performance claims. Concrete reductions are structural: local startup avoids online/API work; immutable version-addressed resources eliminate stale-cache retries and are reused by the PWA; the compiled embed excludes duplicate root web-source copies; Unshare restores the current preview instead of regenerating a maze; service-worker activation removes stale leqra app caches; and shutdown serializes one notice for all clients. Existing hot-path optimizations from previous releases remain intact.
