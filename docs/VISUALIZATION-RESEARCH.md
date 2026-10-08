# WMP 9 Visualization Research

Research date: 2026-10-08. Goal: enough detail to recreate each Windows Media Player 9 Series built-in visualization in a 2D CoreGraphics renderer on an iPad 2, plus a feasibility call on porting projectM/MilkDrop.

**Source caveat.** The WMP Visualization Wiki (wmpvis.fandom.com) was read through its MediaWiki API, which returns wikitext. Its screenshot files sit behind a Cloudflare bot check and could not be downloaded, so visual descriptions come from YouTube thumbnails of real WMP 9/10 captures (video IDs cited per item). Anything inferred only from a preset name is marked *(uncertain)*.

## What shipped in WMP 9 Series (2003)

From the wiki "Versions Available in" fields:

| Family | WMP 9 presets | Notes |
|---|---|---|
| Alchemy | Random (only preset) | New in 9; still in WMP 12. Internal name "Tolerance". |
| Ambience | Random + 13 named | WMP 7 to 10; "Thingus" added in WMP 8. |
| Bars and Waves | Bars, Ocean Mist, Fire Storm, Scope | WMP 7 to 12. Unused "Dot Scope" in the DLL. |
| Battery | Randomization + 25 named | New in WMP 8. **"Battery: Randomization" was the default in WMP 9 and 10.** |
| Particle | Particle, Rotating Particle | "Dotplane" in WMP 7; WMP 7.1 to 10. |
| Plenoptic | Random + 6 named | WMP 7 to 10. |
| Spikes | Spike, Amoeba | WMP 7 to 10. |
| Musical Colors | 21 presets | **WMP 7 to 8 only**, dropped in 9 (video-card issues). Not a WMP 9 built-in. |

All by Averett & Associates for Microsoft. Wiki families: Ambience (Ambience, Battery, Alchemy: video feedback), Bars and Waves (plus Particle, Spikes: direct drawing) and Musical Colors (plus Plenoptic: smeared colour fields).

## Battery (WMP 8 to 12)

The key find: the wiki documents Battery's registry layout (`HKLM\SOFTWARE\Microsoft\MediaPlayer\Battery`), which is the engine's architecture. Every preset is three things, and this is the model to implement:

1. **CurrentShift**: one full-frame displacement ("video feedback") applied to the previous frame each tick. Classes: `CSwirlShift` (mandala swirls), `CRingSpinShift` (kaleidoscope), `CStarburstShift`, `CStretchShift` (tunnel), `CTileShift` (blocks), `CShiitake` (swirl), `CTwirlocity` (natural swirls), `CLinearShift` (scroll up/down/left/right), `CThingusShift`, `CZoomShift`, `CTrigShift`, `CSinShimmerShift` (shimmer), `CEdgeFalloffShift`, `CTrigStretchShift` (trig tunnel).
2. **PreShift / PostShift drawers**: line and curve elements drawn before or after the displacement. Classes: `CJDar` (radar), `CDotPlane` (dot grid), `CCircleWaveform` (waveform bent into circles), `CEdgeGradiant` / `CCosEdgeGradiant` (gradient border), `CJiggyScribble` (fireworks/scribbles), `CEdgeTrace` (border), `CSpectrumEdge` (spectrogram border), `CGalaxy`.
3. **Palette** with a `PaletteLocked` flag. Unlocked (hue cycles): randomization, brightsphere, cottonstar, illuminator, my tornado is resting. Locked: lotus, hizodge, gemstonematrix, sepiaswirl, chemicalnova, green is not your enemy.

Wiki trivia: presets with a dot plane keep its position when switching to *sleepyspray*, *event horizon* or *brightsphere* (so those use `CDotPlane`); *lotus* and *cottonstar* are "very related"; *strawberryaid* appeared in a Windows XP TV advert.

Captures: "Battery: Randomization" in WMP 9 (YouTube 0SxuaMX5oe0): magenta field, black filled oval at centre, bright pink-white ring around it, concentric softer rings and grey swirl trails outward, i.e. a zoom/tunnel shift feeding back a ring. Another (hR06GZWpmJw): dark navy field, grey-white smoke and a bundle of thin diagonal parallel lines through the centre, i.e. dot-plane lines under a swirl shift.

| Preset | Shapes | Driven by | Colours | Motion | Notes |
|---|---|---|---|---|---|
| Randomization | Any below | Random preset and palette | Hue cycles | Switches periodically | WMP 9/10 default. |
| brightsphere, event horizon, sleepyspray | Dot plane (`CDotPlane`) plus a central blob or pull | Volume | Unlocked / dark / pastel | Zoom-in (event horizon), slow linear drift (sleepyspray) *(uncertain)* | Dot plane confirmed by wiki trivia. |
| cottonstar / lotus | Soft radial petal shape | Waveform | lotus locked | Kaleidoscope `CRingSpinShift` *(uncertain)* | "Very related". |
| kaleidovision | Mirrored wedges | Waveform | Multi | `CRingSpinShift` | Codename "kaleidoscope". |
| sepiaswirl | Swirl | Waveform | Sepia, locked | `CSwirlShift` | Codename "GrooveSwirl". |
| green is not your enemy | Scribbles inside a ring *(uncertain)* | Beat | Green, locked | Swirl | A green ring, white centre and dark squiggles in QPrJAJsp_UM is likely this. |
| my tornado is resting | Vertical swirl column | Volume | Unlocked | `CTwirlocity` | Codename "tornado". |
| dance of the freaky circles, cominatcha | Circle waveforms; zoom-toward-viewer tunnel *(uncertain)* | Waveform; beat | — | `CCircleWaveform`; `CZoomShift` | Names only. |
| hizodge, gemstonematrix, chemicalnova, spider's last moment..., smoke or water?, the world, illuminator, dandelionaid, drinkdeep, eletriarnation, i see the truth, relatively calm, strawberryaid, back to the groove | Not documented | — | first three palette-locked | — | Only names and inaccessible gallery images. |

**Implementation reading:** Battery is one engine. Build the 14 shifts and ~9 drawers once; presets become data (shift, drawers, palette, locked flag). Every stroke is softened by repeated displacement with slight decay, so frames read as smoke or liquid, not crisp lines.

## Ambience (WMP 7 to 10)

Battery's calmer older sibling, same feedback engine. Wiki: "fades in and out through several colors. It begins in light blue and transitions between red, orange, yellow, green, cyan, light blue, blue, magenta, pink, purple, peach, and gray." One global hue cycles slowly; each preset is a different displacement under a horizontal waveform.

Captures: *Falloff* (L9hvtAqI2qI): solid red field, white jagged waveform across the centre, previous frames stretched vertically so trails form a dark hourglass pinched at the centre. *Anon* (o5brTKyKa3o): pale cyan field, white lightning-like waveform across the middle, soft cloud blur and a radial star smear at centre from zoom feedback. A pinwheel capture (H0d6tSqyN1Y): magenta/black spiral wedges rotating around centre with jagged waveform lines along wedge edges, probably *Swirl* or *Windmill* *(uncertain)*.

| Preset | Shapes | Driven by | Colours | Motion | Notes |
|---|---|---|---|---|---|
| Swirl | Horizontal waveform | Waveform; flashes white when loud | Cycling | Rotation about centre | |
| Warp | Waveform | Waveform | Cycling | Warp/stretch | |
| Anon | Waveform | Flows left, flips right at high volume | Cycling | Zoom feedback (capture) | |
| Falloff | Waveform | Waveform | Cycling | Edge fall-off, vertical stretch (capture) | |
| Water | Waveform | Flashes white when loud | Cycling, often blue | Ripple displacement *(uncertain)* | Most popular preset per wiki. |
| Bubble | Rounded ring/blob *(uncertain)* | Volume | Cycling | Zoom | Blue oval ring with blocks in 5Xb-japMv6w may be this. |
| Dizzy | Waveform | Flows left; flips at high volume | Cycling | Rotation | |
| Windmill | Waveform | Flashes white when loud | Cycling | Pinwheel rotation | |
| Niagara | Waveform | Flashes white when loud | Cycling | Downward scroll *(uncertain)* | |
| Blender | Waveform | Flows left; flips at high volume | Cycling | Swirl | |
| X Marks the Spot | Waveform | Flashes white; direction by volume | Cycling | Diagonal mirrored shift *(uncertain)* | |
| Down the Drain | Two waveform lines that swap places at high volume | Waveform + volume | Cycling | Spiral inward | |
| Thingus | Waveform | Flashes white when loud | Cycling | `CThingusShift` | WMP 8+. |

## Alchemy (WMP 9 to 12)

One preset ("Random") that cycles internal looks. Captures (3tS9P3DeT_8, XW3XmapaHGc) show the signature elements:

- Soft two-colour gradient background (purple to blue, or dark olive green) with blurred feedback smears.
- Two large translucent radial-gradient **spheres** (green on purple, pink on green) drifting slowly, with a thin **squiggly line** trailing between them.
- A **fan of 10 to 20 parallel wavy lines**: one waveform repeated along a diagonal sheet in perspective (orange/yellow on purple, teal on green), reading as a bent ribbon of waveforms.
- Small purple **lightning scribbles** near the spheres on beats.

| Preset | Shapes | Driven by | Colours | Motion | Notes |
|---|---|---|---|---|---|
| Random | 2 gradient spheres, waveform ribbon, scribble lightning | Waveform (ribbon), beat (lightning), time (spheres) | Complementary pairs: purple+green, green+pink, orange accents | Spheres drift, ribbon rotates slowly, light feedback blur | 3D Alchemy (Creativity Fun Pack) added Classic, Kaleidoscope, Monoliths, Strange World, WM Museum; not built in. |

## Bars and Waves (WMP 7 to 12)

The only analytical family. Wiki: logarithmic frequency scale (Bars is linear at low frequencies, log above), so the left half is "small but blocky". Capture of *Bars* (V3RE915WIBU): black background, dense thin yellow-green vertical bars in the centre, taller on the left, dark peak-hold markers above each bar. Skin mode is pure green (gallery captions).

| Preset | Shapes | Driven by | Colours | Motion | Notes |
|---|---|---|---|---|---|
| Bars | Many thin vertical bars with peak caps | Spectrum (log) | Yellow-green on black | Instant rise, slow fall, slower caps | |
| Ocean Mist | Mirrored waveform, soft | Waveform | Blue-white *(uncertain)* | Short fading trails | Wiki infobox image. |
| Fire Storm | Spectrum rendered as flame | Spectrum | Red/orange/yellow from bottom *(uncertain)* | Flicker, rising smear | |
| Scope | Oscilloscope line | Waveform | Yellow-green (pale green in skins) | None | "Dot Scope" variant unused. |

## Spikes (WMP 7 to 10)

Wiki: "round circles that stretch outward in response to music". Capture (bottom-right panel of c9xVfOmhqYI): yellow starburst on black made of hundreds of thin radial lines, with a jagged outer silhouette following the spectrum around the circle.

| Preset | Shapes | Driven by | Colours | Motion | Notes |
|---|---|---|---|---|---|
| Spike | Radial lines from centre, length per band wrapped around 360 degrees | Spectrum | Yellow (red in WMP 7/8 and skin mode; green in WMP 9 with black background) | Breathes with volume, probably slow rotation *(uncertain)* | |
| Amoeba | Closed blob outline through the spike tips | Spectrum | Yellow (green in skin mode) | Wobbles | Both named in Microsoft's SDK docs. |

## Particle (WMP 7.1 to 10)

Wiki: "a flat, squared-shaped grid with red, purple, blue, and cyan dots". Capture (top-right panel of c9xVfOmhqYI): sparse square dot grid on black, tilted in perspective. This is the `CDotPlane` element alone.

| Preset | Shapes | Driven by | Colours | Motion | Notes |
|---|---|---|---|---|---|
| Particle | Perspective-projected square dot grid | Dot height/brightness from spectrum *(uncertain)* | Red, purple, blue, cyan on black | Plane tilts and ripples | |
| Rotating Particle | Same | Same | Same | Plane rotates; wiki says rotation "breaks" and resets over time | |

## Plenoptic (WMP 7 to 10)

Wiki: "a paint look-a-like". Capture of *Smokey Lines* (s3FSDoeWwAA): the whole frame is vertical streaks of saturated blue, magenta, red, yellow, cyan and green, blurred vertically with a fine vertical line texture, like wet paint dragged down. Wiki on *Smokey Circles*: colours "go from blue and green to yellow and orange first, then later to other arrangements". A *Spyro*/*Fountain*-like capture (Rbd2XUbuLTM, bottom-left of c9xVfOmhqYI): orange-red dotted arcs spraying upward from a bright multicolour blob at bottom centre.

| Preset | Shapes | Driven by | Colours | Motion | Notes |
|---|---|---|---|---|---|
| Smokey Circles | Soft filled circles stamped per beat, then smeared | Beat | Blue+green, then yellow+orange | Heavy blur feedback | |
| Smokey Lines | Vertical colour streaks | Spectrum across x *(uncertain)* | Full rainbow | Vertical smear | |
| Vox | Waveform-shaped smear *(uncertain)* | Waveform | — | Smear | Name only. |
| Flame | Rising flame | Spectrum | Red/orange/yellow | Upward smear | |
| Fountain | Particle arcs from bottom centre | Beat | Orange/red on black | Fall under gravity | |
| Spyro | Spiral arcs from centre | Beat | Multicolour | Rotation | |

## Musical Colors (WMP 7 to 8, not in 9)

21 presets (Night Lights, Colors in Motion, Aurora, Rhythmic Colors, Star Power, Electric Green, Soft Fire, Silky Wave, CutOut, Rolling Fire, Water Spray, Acid Rock, Hard Rock, Hot Spray, Yellow Swirl, Blue Flame, Critter Rock, Electric Rainbow, Neon Highway, WinMe 3D, Ice Crystals). Capture of *Soft Fire* (xpoUgJu3VBE): spectrum columns rendered as a fire gradient, yellow at the bottom through orange to dark red tips, full width on black. A cheap "flame spectrum" look worth borrowing even though it is not a WMP 9 item.

---

## Part B: projectM / MilkDrop feasibility on iPad 2

Target: iOS 9.3.5, ARMv7 (A5, PowerVR SGX543MP2), **OpenGL ES 2.0 maximum** (ES 3.0 needs A7), 512 MB RAM, 2016-era libc++.

### What the presets are

`presets-milkdrop-original` (cloned 2026-10-08: 552 `.milk` files, 6.8 MB; the pack shipped with the last official MilkDrop). Each `.milk` is an INI file: a `[preset00]` block (`fDecay`, `zoom`, `rot`, `warp`, `nWaveMode` 0 to 7, `bAdditiveWaves`, borders, motion vectors), up to 4 custom waves and 4 custom shapes with their own `per_frame`/`per_point` code, global `per_frame_N=` and `per_pixel_N=` equations evaluated on a warp mesh, and for MilkDrop 2 presets `warp_1=`/`comp_1=` HLSL pixel-shader bodies tagged `PSVERSION` 2 or 3.

| Category | Files |
|---|---|
| No `PSVERSION` and no `warp_1`/`comp_1` code (MilkDrop 1 style, fixed-function renderable) | 303 |
| `MILKDROP_PRESET_VERSION=201` with pixel shaders | 249 (202 need PS 2.0, 47 need PS 3.0) |

Just over half the pack needs no pixel shaders. Those 303 are what a GLES 1/2 renderer could show; the rest need an HLSL-to-GLSL-ES-1.00 translator and the SM3 ones would still fail.

### projectM versions

| Version | Date | Language / GL | Verdict |
|---|---|---|---|
| **4.1.8** (master) | 2026-10-06 | `CMAKE_CXX_STANDARD 14`; docs: "OpenGL Core 3.3 or OpenGL ES 3.2"; `ENABLE_GLES` is "OpenGL ES 3 profile"; glad loader; CMake 3.21+; GLM bundled; SDL only for the test UI; docs list iOS/tvOS as building. | **No.** Needs ES 3. C++14 is fine, but the renderer (HLSL-to-GLSL translation, blur textures, `#version 300 es`) would need a rewrite for GLSL ES 1.00. |
| **3.1.12** | 2021-02-20 | C++11 (autotools `-std=c++11`); `--enable-gles` defines `USE_GLES`, includes `GLES3/gl3.h`, forces `#version 300 es`. | **No**, same reason; a smaller fork than 4.x but still a renderer backport. |
| **2.2.1** (last 2.x; code 2009 to 2012) | 2018-04-06 | C++03-era; fixed-function GL with a `USE_GLES1` path (`GLES/gl.h`, `GL_CLAMP_TO_EDGE`, skips `glDrawBuffer`/`glLineStipple`); FBOs via `EXT_framebuffer_object` with `glCopyTexSubImage2D` fallback; MilkDrop 2 shaders only via NVIDIA Cg (`USE_CG`), so none on iOS; defaults mesh 32x24, texture 512, 35 fps; optional FTGL; OpenMP via `omptl`. | **Plausible.** iPad 2 on iOS 9 still offers an ES 1.1 EAGL context. Rename `EXT` FBO calls to `OES`, drop Cg/FTGL, add an EAGL render target and PCM feed. Renders the 303 non-shader presets only. |

The claim in search summaries that projectM "was ported to OpenGL ES 2 for ARM in 2011" could not be verified in the repository or on Wikipedia (which lists projectM only as cross-platform OpenGL/C++, LGPL 2.1, with an Android app); treat as *(uncertain)*. The Play Store app is a third-party 2.x-era build the projectM team does not support.

### Effort and recommendation

- A **projectM 2.2.1 GLES1 port** is roughly 2 to 4 weeks for someone comfortable with legacy GL and iOS builds: Xcode target for the C++ sources, ES1 context, OES framebuffer patches, audio bridge, preset loading, then tuning (mesh 32x24 or smaller, texture 512, 30 fps cap). Memory is small (two 512x512 textures plus presets). CPU cost is the per-vertex equation interpreter over 768 mesh points, fine on an A5. The result is a real MilkDrop 1 engine with ~300 presets, but it is a second renderer stack (GL plus a C++ interpreter), LGPL, and it looks nothing like WMP 9.
- **projectM 3.x/4.x are not realistic** on this GPU without a renderer rewrite.
- **Recommendation:** stay with hand-written 2D renderers for the WMP 9 looks and borrow MilkDrop's frame-feedback model, which is also what Battery and Ambience are built on. Keep the 2.2.1 port as an optional later "MilkDrop" visualization.

## Techniques to borrow for a 2D renderer

1. **Frame feedback with decay.** Keep an offscreen bitmap context at half resolution (512x384 is plenty on an A5). Each frame draw the previous frame back with alpha 0.90 to 0.98 (MilkDrop `fDecay`), then draw new strokes on top. This one step gives the smoke/trail look of Battery, Ambience, Plenoptic and Alchemy.
2. **Zoom/rotate/translate the feedback on the GPU.** Keep the previous frame in a `CALayer` and apply a `CATransform3D` scale (1.01 to 1.05 = MilkDrop `zoom`), rotation (`rot`) and offset (`dx`, `dy`) about a centre (`cx`, `cy`); Core Animation composites it. Snapshot the result for the next frame, or stack two layers and swap. This covers `CZoomShift`, `CStretchShift`, `CLinearShift` and swirl-ish rotation almost free.
3. **Non-affine shifts via a coarse warp mesh.** MilkDrop evaluates `per_pixel` equations on a 32x24 grid and lets the GPU interpolate. Approximate with a grid of small quads, or a low-resolution displacement table applied with `vImage` on the CPU. Kaleidoscope: mirror angles into one wedge and draw it N times rotated. Covers swirl, kaleidoscope and tunnel.
4. **Waveform modes.** Reuse MilkDrop `nWaveMode` ideas: 0 circle, 1 x-y spiral, 2/3 centred lines, 4/5 horizontal line variants, 6/7 vertical/mirrored. Ambience is mode 4/5; Alchemy's ribbon is mode 4 drawn 10 to 20 times with progressive offset and rotation; Battery's `CCircleWaveform` is mode 0.
5. **Beat detection from bass energy.** projectM's `BeatDetect` keeps running averages of bass/mid/treble energy; treat `bass > 1.3 * bass_avg` with a 150 ms refractory as a beat. Use for Plenoptic stamps, Alchemy lightning and Ambience's "flash white when loud" (Swirl, Water, Windmill, Niagara, X Marks the Spot, Thingus).
6. **Palette cycling.** One global HSB hue phase advanced per frame (Ambience's documented colour order) plus a per-preset `PaletteLocked` flag as in Battery's registry.
7. **Peak-hold spectrum bars** for Bars and Waves: instant attack, exponential release, slower-falling cap, log-spaced bands.
8. **Perspective dot plane** for Particle: a 2D grid through a simple 3D rotation, 4-colour dot table, dot size by depth.

## Sources

- WMP Visualization Wiki pages Battery, Ambience, Alchemy, Bars and Waves, Particle, Plenoptic, Spikes, Musical Colors, 3D Alchemy, the three Family pages, gallery subpages and the Default/Visualizations categories, via `https://wmpvis.fandom.com/api.php`, 2026-10-08.
- Microsoft Learn, WMP SDK "User Overview" (Ambience/Plenoptic/Spike; presets Spike and Amoeba): https://learn.microsoft.com/en-us/windows/win32/wmp/user-overview, 2026-10-08.
- YouTube captures (thumbnails read 2026-10-08): 0SxuaMX5oe0, hR06GZWpmJw (Battery); L9hvtAqI2qI, o5brTKyKa3o, H0d6tSqyN1Y, 5Xb-japMv6w (Ambience); 3tS9P3DeT_8, XW3XmapaHGc (Alchemy); V3RE915WIBU (Bars); c9xVfOmhqYI (Ambience/Particle/Plenoptic/Spikes 4-up); s3FSDoeWwAA, Rbd2XUbuLTM (Plenoptic); xpoUgJu3VBE (Musical Colors); QPrJAJsp_UM (probable Battery).
- projectM: https://github.com/projectM-visualizer/projectm, read 2026-10-08 at tags master (v4.1.8), v3.1.12 and v2.2.1: `CMakeLists.txt`, `docs/building.rst`, `configure.ac`, `projectM-opengl.h`/`OpenGL.h`, `Renderer/StaticGlShaders.cpp`, `Renderer/Renderer.cpp`, `Renderer/FBO.cpp`, `Renderer/ShaderEngine.cpp`, `projectM.cpp`. Dates from the GitHub releases API.
- MilkDrop presets: https://github.com/projectM-visualizer/presets-milkdrop-original, cloned 2026-10-08; counts by grep.
- MilkDrop preset authoring guide: https://www.geisswerks.com/milkdrop/milkdrop_preset_authoring.html, 2026-10-08.
- Wikipedia, MilkDrop (projectM row; MilkDrop 2.0 pixel shaders, 2007): https://en.wikipedia.org/wiki/MilkDrop, 2026-10-08.
