# leqra v4.39.0

## Larger, crisp app icons

App icons are rendered directly from the existing SVG artwork, preserving the tank design and colors. No smaller PNG is enlarged.

- Regular PWA icons: 192, 512 and 1024 pixels square.
- Maskable PWA icons: 512 and 1024 pixels square, with an opaque dark background and artwork inside the safe circle. This also removes the previous white corner artifacts.
- Apple touch icons: 180 and 512 pixels square.
- Favicon: scalable SVG declared with `sizes="any"`, plus a 256-pixel PNG fallback.

The manifest, HTML, server routes and offline cache include the new assets. `scripts/render-icons.py` can reproduce them from `web/favicon.svg` using Inkscape. Installed icon selection and refresh are controlled by the browser/operating system; their actual device behavior was not tested here.

## Shots appearing to pass through tanks

Two separate problems were reproduced and fixed.

**Close-range projectile misses:** spawning a projectile swept from the tank center to the end of its barrel against walls, but skipped tanks along that segment. A grazing tank could be entirely behind the projectile's initial position, so the later movement collision checks missed it. Local and server firing now sweep both walls and tanks, resolve the earliest eligible impact immediately and avoid publishing a projectile that has already hit. This applies to ordinary shells, shotgun pellets, machine-gun rounds, missiles, grenades and Cannon. Launch and flight share impact handling, including shields and grenade contact rules.

**Misleading online laser effects:** a local beam preview expires after 230 ms, but sound deduplication lasts longer. A late server confirmation could therefore have its corrected beam hidden. The confirmed path now appears even after the preview expires; a still-live preview is corrected without extending its life. Remote laser hit and shield effects now bring forward their matching buffered beam and sound, so the impact no longer appears before the beam. Repeated event history and sounds remain deduplicated.

No defect was demonstrated in the server's direct or reflected laser intersection calculation. Spawn-protected tanks and allies with friendly fire off intentionally do not take laser hits. Shields absorb a hit. Online damage continues to use server positions: a predicted beam can disagree with a moving target's displayed position under latency. This release fixes missing confirmation visuals, not that underlying latency or the authority model.

## Collision-query optimization

Multi-cell wall queries now deduplicate candidates with reusable ordered bit masks instead of sorting wall IDs each time. Wall order, exact collision results, corner normals, single-cell reuse and broad-query fallback are preserved.

In the isolated Node benchmark, complete wall queries used 37% less time for movement, 53% less for aiming and 49% less for long laser/scope-style sweeps. These are query timings, not game FPS or phone-performance measurements. See `PERFORMANCE-v4.39.0.md` for the fixture and raw results.

## Install

Replace the Go sources and the complete `web/` folder, then rebuild and restart:

```sh
go build -trimpath -o leqra .
./leqra
```

Refresh clients afterward. Server, browser assets, PWA registration and offline cache use **4.39.0**. Online clients and server must have matching versions.

See `TEST-NOTES-v4.39.0.md` for executed verification and limits. Previously proposed broader UI restructuring remains unimplemented.
