# leqra v4.40.0

## Mobile selection and zoom

During an active match, the complete mobile UI blocks native text selection, selection highlighting, touch callouts and tap highlighting. This includes both pilots' ammo/status areas, weapon timers, feedback messages, the sidebar, menus and dialogs.

The existing gesture policy now includes an explicit Safari double-tap fallback, with document-level selection and double-click guards. Single-finger menu scrolling, ordinary button clicks, keyboard focus and independent joystick/Fire pointers remain available. Text fields retain caret typing and IME composition. The guards clear an old selection at match start, avoid repeatedly changing a collapsed selection, and are removed when returning to the lobby or final results.

The compact final results preview previously released the touch lock too early because the simulation already reported the match as over. It now retains protection through that preview, as well as pauses, round breaks and an interrupted online reconnect.

## Fixed power-up icon positions

Bot and remote-tank power-up icons use the same close clockwise slots relative to the tank everywhere in the maze. They no longer move into alternate positions when approaching an edge or corner. Gaining or losing a power-up can change which icon occupies a slot; movement, rotation and timer/charge changes do not. Names stay in their existing fixed positions.

Icons at the maze boundary may be clipped by the arena rather than moved to a different slot. Removing the edge-search loop also eliminates its repeated alternative-position checks.

## Audio

The requested base sound-effect gain is doubled. The Controls slider still defaults to **50%**, now requesting twice the previous gain; **100%** requests another doubling. Existing saved slider values, midpoint snapping, mute and short volume ramps are preserved.

Web Audio applies the increase through the shared master gain, with shared peak control for loud overlapping effects. Quiet signals retain their gain; compressed peaks leave output headroom. Effect waveforms, pitch, timing and individual fades are retained.

The native Safari fallback uses smooth whole-wave gain scaling for louder sounds. It preserves each waveform's shape, stays below full-scale output and continues increasing through 100%, without the previous hard gain plateau. This requires reducing the boost for loud fallback effects already near the output ceiling. The adjustment is therefore a doubled base gain with peak protection, not exactly doubled perceived loudness for every effect or device.

Removed the paragraph beginning “The midpoint is the original leqra volume…” from Controls, including its empty paragraph element.

## Install

Replace the Go sources and complete `web/` folder, then rebuild and restart:

```sh
go build -trimpath -o leqra .
./leqra
```

Refresh clients afterward. Server, browser, versioned assets and offline cache use **4.40.0**. Online client and server versions must match. High-resolution icons and all earlier gameplay fixes are retained.

See `TEST-NOTES-v4.40.0.md` for validation and the remaining physical-device checks.
