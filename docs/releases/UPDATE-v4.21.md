# leqra v4.21 — Safari audio, volume controls, and reliable chat routing

## Why audio could be silent in Safari

Safari and iOS Safari enforce Web Audio user-activation rules more strictly than many Chromium configurations, and `AudioContext.resume()` can finish asynchronously. v4.20 requested a resume and then immediately attempted to create/play a tone only when `AudioContext.state === "running"`. On Safari, the context could still report `"suspended"` for that moment, so the first effect or minimized-chat notification was discarded even though the resume completed shortly afterward.

v4.21 changes the audio path so playback waits for the resume promise to settle. Pointer, touch, and keyboard gestures also retry the unlock when WebKit initially blocks it. Game effects and minimized-chat notifications go through the same ready-state gate instead of maintaining separate timing assumptions.

This improves Safari reliability without bypassing the browser's autoplay policy: the first audible playback still ultimately requires browser-permitted user interaction.

## Volume control

The Controls menu now includes a persistent **VOLUME** slider from 0–100.

- **50% is the old v4.20 output level** and the default/current midpoint for users who have never set a volume.
- Moving within the center snap zone (46–54) snaps to exactly **50%**, making the original level easy to recover.
- 0% is silent; 100% is up to 2× the old master gain.
- The setting is saved on this device as `leqra.volume`.
- The existing sound button / M shortcut remains an independent mute rather than rewriting the slider value.
- Releasing the slider previews the selected volume when sound is enabled.

The gain is applied at one master node, so ordinary effects, explosions, warnings, and chat notifications all follow the same level.

## Chat destinations are explicit

v4.20 exposed two buttons during matchmaking, but several layers still treated the normal channel as a generic battle-room broadcast. The browser also had a concrete state-selection bug: the helper used by active chat rendering defaulted to the literal `room` channel instead of the channel currently open. That could make the opponent panel read or mutate room-channel state.

v4.21 uses these rules:

### Ordinary online room

**Room chat** reaches current members of that room, as before.

### Queued matchmaking battle

**Party chat — YOUR PARTY ONLY** is the normal chat button. It reaches only players who travelled into the temporary matchmaking room from the same private source party.

**Enemy chat — ENEMY SIDE ONLY** is the red chat button. It reaches the sender and the opposing matchmaking side. It does not reach the sender's teammates. Free-for-all treats each other participating side as an opponent.

Side-less matchmaking spectators do not get either private tactical channel. The server determines party/side membership; clients cannot name arbitrary recipients.

## Chat reliability fixes

- Fixed the active-channel helper so the opponent panel actually uses opponent state.
- Party and enemy channels now keep independent message history, unread counts, errors, pending sends, and **draft text**.
- Switching buttons preserves each channel's unsent draft instead of carrying it into the other destination.
- A server echo clears only that channel's pending send and cannot erase text being composed in the other channel.
- Normal and enemy broadcasts deduplicate the underlying WebSocket connection, so a controller owning local P1 + P2 receives one rendered copy rather than duplicate messages.
- Matchmaking party history is filtered on reconnect using the same source-party rule as live delivery.
- Unrelated matchmaking spectators do not receive private party messages.
- Minimized-channel notification audio uses the Safari-safe resume/queue path.

## Install / upgrade

Back up deployment-specific configuration, replace all Go source files and the complete `web/` directory, then rebuild/restart because the browser assets are embedded:

```sh
cd leqra-online
go build -trimpath -o leqra .
./leqra
```

For development:

```sh
go run .
```

Refresh all players after restarting. `/healthz`, `/api/config`, the Controls footer, and `leqra.version` should report **4.21.0**. Existing in-memory rooms reset on server restart. Existing local controls/preferences remain, and users without a stored `leqra.volume` start at the original 50% midpoint.
