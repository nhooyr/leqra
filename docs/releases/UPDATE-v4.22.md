# leqra v4.22 — Safari audio fallback, integrated match chat, Ghost smoothing, and room UX

## Safari audio now has a native fallback

v4.21 fixed an asynchronous Web Audio resume race, but the served Safari fallback still had a second problem: it renders short native-audio tones as generated WAV `blob:` URLs while the server Content-Security-Policy did not allow `blob:` media. Safari could therefore unlock correctly and still have the fallback blocked by the page itself.

v4.22 adds `media-src 'self' blob:` to the served CSP. Safari also primes a small pool of native HTML audio elements on pointer/touch/keyboard activation and starts a real one-frame Web Audio source inside the same trusted gesture. Once audio is unlocked, that priming path is idempotent instead of repeating eight native play attempts and a silent Web Audio source on every click/touch. If WebKit suspends/interrupts audio later, a real user gesture can retry the unlock.

The existing volume slider, 50% midpoint snap and mute behavior remain unchanged. Desktop Safari again receives a dismissible recommendation for **Chrome or Firefox**; iPhone/iPad Safari does not show that desktop notice.

## One integrated matchmaking chat

Matchmaking now uses the normal chat button and one transcript. Incoming enemy messages are visibly tagged **OPPONENT** in red. The compose area contains one compact **Send to opponent** switch. Leave it off to send to the travelling party; turn it on to send to the opposing matchmaking side. The send button/placeholder update to make the currently selected destination explicit.

The server still keeps the channels separate internally so privacy is authoritative. The browser merely merges the two filtered histories for display. Ordinary non-match rooms continue to use room-wide chat. Side-less match spectators do not receive the private tactical chat control.

## Ghost movement smoothing

Two separate Ghost effects could feel like a sideways pull. Online prediction could retain a normal visual reconciliation offset while the tank was phasing through geometry; Ghost reconciliation now clears that positional smoothing while Ghost is active and across its transition. In addition, a ghosted tank could overlap another tank on the opposite side of a wall and the ordinary tank-to-tank separation force could push the ghosted tank laterally through that wall. The authoritative Go simulation and local browser simulation now skip that cross-wall separation while Ghost is active. Same-side tank collisions remain normal.

## Room and roster UX

- Hosts can **Unshare room** beside the room exit controls. It removes the public server room, disconnects remote players/spectators, and restores the host locally with the same room name, rules, bots and local Player 2.
- Shared P1/P2 WebSockets are deduplicated during Unshare teardown, preventing duplicate offline packets.
- The in-match **Leave online room** action is removed.
- **Join another room** now has one **JOIN** action. A missing room is still created automatically with the joining player as host.
- Callsigns save automatically on Enter or when the field loses focus; explicit Save buttons are gone.
- Online room-code renaming likewise saves on Enter or blur; the Rename button is gone.
- Rules/preset dropdowns use a custom chevron with substantially more right-side breathing room.

## Install

Replace the Go source and complete `web/` directory, then rebuild because the browser assets are embedded:

```sh
cd leqra-online
go build -trimpath -o leqra .
./leqra
```

Refresh every browser. `/healthz`, `/api/config`, the Controls footer and `leqra.version` report **4.22.0**.
