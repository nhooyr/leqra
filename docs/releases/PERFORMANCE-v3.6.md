# leqra v3.6 — measured drawing work and renderer decision

## What changed

The previous renderer rebuilt every tank hull and fourteen tread lines each frame.
The new renderer pre-renders that static artwork to reusable small offscreen 2D
canvases. Color, four tread phases and resolution select a cached image. Turrets,
recoil, shields, boosts and aim/missile indicators still update each frame.

The hull cache has at most 96 images; text-width caching has at most 192 entries.
Normal eight-color/tread combinations use about 32 images at a single resolution
(about 1.13 MiB of raw 96×96 RGBA pixels, before browser overhead). The actual
benchmark used 14 entries. Resolution variants can use more memory, but stay bounded.
These are regular detached canvases, not a worker-based OffscreenCanvas renderer.

No change is made to the collision index, fixed simulation rates, weapon timing,
server snapshot schedule or netcode.js prediction/interpolation core. The flag
layer change is a painter-order correction, not a new 3D renderer.

## Controlled cache A/B

Same v3.6 client, same frozen **eight-tank 14×12** scene, **1365×950**, DPR 1,
headless Chromium on this container. The test-only hull-cache switch is the sole
rendering change between conditions. Both conditions already use cached label
widths. This comparison isolates the hull cache; it is not a comparison of two
complete releases or a worst-case missile/particle battle.

Eight alternating batches each submit 150 complete scene renders, with waits
between batches. These times measure synchronous **JavaScript/Canvas command
submission**, not completion of GPU/raster work. Separate six-second animation
frame samples use the normal frame loop and a frozen simulation.

| Measurement | Vector hulls | Cached hulls |
| --- | ---: | ---: |
| Median command-submission time per complete scene | 1.136 ms | 0.121 ms |
| Main-canvas path starts per scene | 216 | 56 |
| Main-canvas stroke calls per scene | 143 | 23 |
| Main-canvas drawImage calls per scene | 1 | 9 |
| Mean animation-frame interval | 16.666 ms | 16.666 ms |
| Frames exceeding 25 ms in RAF sample | 0 | 0 |

That is approximately 89.3% less measured command-submission time in this
specific workload, with 160 fewer path starts and 120 fewer stroke calls per frame.
**Both conditions were already about 60 FPS. This is not a 9.4× FPS or whole-game
speedup**, nor a guarantee on another CPU/GPU/browser. Sprite filtering may differ
slightly from direct vector edge antialiasing at particular screen scales.

Raw measurements and trial order: `tests/results/performance-v3.6.json`.
Reproduce with optional Playwright/Chromium test tools:

```sh
python tests/performance36_browser.py . test-output/performance36
```

## Why not claim WebGL is automatically faster?

WebGL can render this 2D game. An effective port would batch tank/particle quads,
use texture atlases and avoid excessive state/draw-call changes. Simply uploading
a freshly rendered Canvas image to a WebGL texture each frame would preserve the
original drawing work and add a transfer, rather than removing that workload.

A full port would also need readable text/icons, clipping and layer parity,
context-loss recovery and an appropriate fallback. It should be measured on actual
phones and desktop GPUs. This run has not implemented or benchmarked a WebGL port,
so it provides **no evidence of a WebGL FPS gain for this game**.

The bounded sprite cache is a lower-risk optimization of a known repeated operation.
The prior spatial collision index, shared encoded snapshots, bounded UI updates and
Performance graphics option remain. Those address different costs; changing the
rendering API would not directly fix server CPU or network latency.

## Remaining optimization candidates

Profile projectile trails/glow in an eight-tank combat-heavy scene on a physical
phone; consider adaptive effects before reducing simulation quality. If rendering
is then the dominant cost, compare a batched WebGL sprite renderer with this Canvas
path at matched visual quality. If CPU planning dominates local play, profile bot
pathfinding/threat forecasts separately rather than assuming the GPU is responsible.

## References

- MDN, Optimizing canvas (pre-rendering repeating objects):
  https://developer.mozilla.org/en-US/docs/Web/API/Canvas_API/Tutorial/Optimizing_canvas
- MDN, WebGL best practices (batching and texture atlases):
  https://developer.mozilla.org/en-US/docs/Web/API/WebGL_API/WebGL_best_practices

These references support the techniques, not the game-specific benchmark results.
