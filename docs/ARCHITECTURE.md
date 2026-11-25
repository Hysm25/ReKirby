# Project Architecture (`docs/ARCHITECTURE.md`)

> **Project**: **ReKirby** — Clean-Room PC & Android Port of **Kirby's Adventure** (NES / Famicom, 1993, Mapper 4 MMC3) in **Godot 4 (Strictly Typed GDScript)**.  
> **Goal**: Faithful, frame-accurate NTSC 60Hz re-implementation featuring deterministic 60 TPS simulation, **Mandatory Runtime ROM Ingestion** from a local git-ignored `.nes` file in `rom/`, zero copyrighted assets committed to version control, and zero mod-loaders or custom skin subsystems.

---

## 1. Legal & Clean-Room Asset Boundary

This project is an independent clean-room software re-implementation built strictly through observed game mechanics, published NES/MMC3/2A03 hardware specifications, and runtime extraction of user-supplied ROM data.

### Boundary Invariants & Mandatory ROM Ingestion
1. **Zero Copyrighted Assets in Repository**:
   - Absolutely no Nintendo / HAL Laboratory ROM binaries, PRG code, CHR graphics dumps, level maps, or audio recordings are committed to version control.
   - `.gitignore` strictly excludes `*.nes`, `rom/*.nes`, `rom/*.bin`, `.godot/`, and all runtime-extracted directories (`nes_data/`, `extracted/`, `user/`).
   - **Zero Mod-Loaders / Zero Custom Skins**: No skin loaders, custom palette overrides, or mod frameworks exist in the codebase. Visuals and audio come exclusively from the authenticated ROM.
2. **Mandatory Runtime ROM Ingestion (Zero Procedural Fallbacks)**:
   - **No Procedural Fallbacks**: The engine contains zero hardcoded tile graphics, level layouts, or synthetic placeholder audio tables.
   - **Startup Guard & Missing ROM Screen**: On boot, the engine checks `user://nes_data/` for extracted assets. If absent, it searches `rom/` (and fallback workspace root) for a valid `Kirby's Adventure` `.nes` image to ingest automatically. If no valid ROM is found, gameplay initialization halts immediately and displays a Missing ROM setup screen.
3. **ROM Verification (`src/importer/rom_validator.gd`)**:
   - Validates the iNES header (`NES\x1A`), Mapper 4 (MMC3), 512 KB PRG-ROM (`32 x 16 KB`), 256 KB CHR-ROM (`32 x 8 KB`), and battery-backed 8 KB PRG-RAM flag (`0x42`).
   - Verifies against authentic NTSC **Kirby's Adventure (USA) (Rev A)** checksums:
     - **Full iNES (786,448 bytes)**: SHA-256 `34afcebaf04d57a42c2436fb95b933c7841e1621f1dc3be482380baef33ec3d8` | CRC32 `0x9EFD5757`
     - **PRG-ROM (524,288 bytes)**: SHA-256 `da723759b15e5c468aa7817a8d57b5e41a694ae9f504eab381e3fa8758027156` | CRC32 `0x8FFF3F32`
     - **CHR-ROM (262,144 bytes)**: SHA-256 `7e6189a311a4dee04b63935ac2218586a6e3a57b506e57b3b03e3545f87b2182` | CRC32 `0x7EDAE6F3`

```text
+-----------------------------------------------------------------------------------+
|                        Mandatory ROM Ingestion Pipeline                           |
|                                                                                   |
|  +-------------------------------------+                                          |
|  | User-Provided .nes ROM in rom/      |                                          |
|  | (512KB PRG-ROM + 256KB CHR-ROM)     |                                          |
|  +------------------+------------------+                                          |
|                     |                                                             |
|                     v                                                             |
|  +-------------------------------------+        NO                                |
|  | iNES & Checksum Validator           | -----------------> [ Missing ROM Screen ]|
|  | (Mapper 4 MMC3, SHA-256 / CRC32)    |                    [ Halt Gameplay Boot ]|
|  +------------------+------------------+                                          |
|                     | YES                                                         |
|                     v                                                             |
|  +-------------------------------------+                                          |
|  | Runtime Extractor (user://nes_data/)|                                          |
|  |  * 2BPP CHR Banks -> PNG Atlases    |                                          |
|  |  * HAL LZ77/RLE Level & UI Streams  |                                          |
|  |  * 16x16 Metatiles & Palettes       |                                          |
|  |  * 2A03 APU Sequences & DPCM Samples|                                          |
|  +------------------+------------------+                                          |
|                     |                                                             |
|                     v                                                             |
|  +-------------------------------------+                                          |
|  | ContentRegistry & AudioManager      |                                          |
|  +------------------+------------------+                                          |
|                     |                                                             |
|                     v                                                             |
|  +-------------------------------------+                                          |
|  | 60 TPS Simulation & Scanline Split  |                                          |
|  +-------------------------------------+                                          |
+-----------------------------------------------------------------------------------+
```

---

## 2. NTSC 60Hz NES Hardware & MMC3 Specifications

ReKirby targets authentic NTSC NES timing (Ricoh 2A03 CPU @ `1.789773 MHz`, 2C02 PPU @ `5.369318 MHz`, `~60.0988 Hz` VBlank) paired with **Nintendo MMC3 (TxROM, iNES Mapper 4)** bank switching and raster IRQ splitting.

| Specification | Authentic NES / MMC3 Value | Godot 4 Engine Mapping |
| :--- | :--- | :--- |
| **Native Resolution** | 256 x 240 pixels | `viewport_width = 256`, `viewport_height = 240` |
| **Stretch & Scaling** | Pixel-aspect / Widescreen-safe integer/canvas | `stretch/mode = "canvas_items"`, `stretch/aspect = "keep"` (or `"expand"` for touch HUD margins) |
| **Texture Filter** | PPU Nearest-Neighbor | `default_texture_filter = 0` (Nearest) |
| **Renderer** | Low-overhead GL Compatibility | `rendering/renderer/rendering_method = "gl_compatibility"` (OptiPlex i5-2400 & Adreno 710 friendly) |
| **Simulation Tick Rate** | 60 TPS NTSC VBlank | `physics_ticks_per_second = 60` (`_physics_process`) |
| **PRG-ROM Capacity** | 512 KB (64 x 8 KB MMC3 banks) | Virtual MMC3 bank mapper (`$8000-$9FFF`, `$A000-$BFFF`, `$C000-$DFFF`, `$E000-$FFFF` fixed) |
| **CHR-ROM Capacity** | 256 KB (256 x 1 KB MMC3 banks) | Virtual CHR bank mapper (2 x 2 KB + 4 x 1 KB slots with `$8000` bit 7 A12 inversion) |
| **Scanline Split** | MMC3 IRQ Counter (`$C000-$E001`) | Dedicated two-pass viewport / CanvasLayer split at scanline Y = 192 |

### 2.1 MMC3 Bank Switching Model (`src/importer/mmc3_mapper.gd`)
Kirby's Adventure dynamically swaps PRG and CHR banks per room, level state, animated background frame, enemy set, and HUD split:
- **Bank Select (`$8000`) & Bank Data (`$8001`)**:
  - `R0`, `R1`: Two 2 KB CHR banks (even-aligned, bit 0 ignored).
  - `R2`–`R5`: Four 1 KB CHR banks (used for per-frame sprite animation, Copy Ability icons, and animated background tiles such as water/clouds).
  - `R6`, `R7`: Two 8 KB PRG banks (`$8000-$9FFF` / `$C000-$DFFF` depending on PRG bank mode bit 6, `$A000-$BFFF`, while `$E000-$FFFF` remains fixed to bank `0x3F`).
- **Nametable Mirroring (`$A000`) & WRAM Protect (`$A001`)**:
  - Dynamically switches between Vertical (`0`) and Horizontal (`1`) nametable mirroring depending on room scroll orientation (horizontal stages vs. vertical shafts/towers).
- **Virtual Bank Resolution**:
  - During extraction and runtime lookup, PRG CPU addresses (`$8000-$FFFF`) resolve through the active MMC3 bank table into flat `0x00000–0x7FFFF` ROM offsets, allowing authentic pointer tables and compressed stream lookups without duplicating assets.

### 2.2 MMC3 Scanline IRQ Split (Bottom HUD)
Kirby's Adventure uses the MMC3 scanline counter (triggered by PPU A12 rising edges) to split the 256x240 frame into two independent rendering regions:
1. **Top Playfield Region (`Y: 0..191`, 24 tile rows)**:
   - Driven by the level camera scroll offset (`scroll_x`, `scroll_y`).
   - Uses the active room's CHR background banks and animated tile swaps (`R0–R5`).
   - Renders parallax/scrollable tilemap layers, 8x8/16x16 OAM actors, projectiles, and particle bursts.
2. **Bottom Status HUD (`Y: 192..239`, 6 tile rows / 48 px)**:
   - Triggered at scanline `191`/`192` via MMC3 IRQ latch (`$C000`) + reload (`$C001`).
   - Locks scroll to `(0, 0)`, swaps CHR banks to the dedicated HUD pattern banks (status frame, 6-bar HP meter, score/lives digits, Copy Ability card portrait), and selects the fixed HUD palette.
   - In Godot 4, this is modeled cleanly with a clipped **Playfield Viewport/Canvas** (`256 x 192`) stacked above a fixed **HUD CanvasLayer** (`256 x 48` at `Y = 192`) so HUD portraits and borders remain razor-sharp and scroll-independent.

---

## 3. Data Extraction & Decompression Specifications

### 3.1 HAL Laboratory LZ77 / RLE Decompression (`src/importer/hal_decompressor.gd`)
Kirby's Adventure stores level room layouts, metatile dictionaries, nametable screens, and select tile blocks using HAL Laboratory's LZ77/RLE bitstream format:
- **Control Byte Decoding**:
  - `0xFF`: End of compressed stream.
  - Otherwise, extract command type `cmd = (byte >> 5) & 0x07` and length:
    - If `cmd < 7`: `length = (byte & 0x1F) + 1`.
    - If `cmd == 7`: Extended length mode — `cmd = (byte >> 2) & 0x07`, `length = (((byte & 0x03) << 8) | next_byte) + 1`.
- **Supported Opcodes (`0..6`)**:
  - `0` (**Raw Literal**): Copy `length` uncompressed bytes from stream.
  - `1` (**8-bit RLE**): Read 1 byte `v`, emit `v` repeated `length` times.
  - `2` (**16-bit RLE**): Read 2 bytes `(v0, v1)`, emit `(v0, v1)` pair repeated `length` times.
  - `3` (**Incrementing RLE**): Read 1 byte `v`, emit `v, v+1, v+2, ...` (`& 0xFF`) for `length` bytes.
  - `4` (**LZ77 Copy**): Read 16-bit big-endian offset `off`, copy `length` bytes starting from `output[off]`.
  - `5` (**LZ77 Bit-Reversed Copy**): Read 16-bit big-endian offset `off`, copy `length` bytes from `output[off]`, reversing the 8 bits of each copied byte (used heavily for horizontally flipped tile/map symmetry).
  - `6` (**LZ77 Backward Copy**): Read 16-bit big-endian offset `off`, copy `length` bytes stepping backwards (`off, off-1, off-2, ...`).

### 3.2 2BPP CHR Planar Tile & Palette Extraction (`src/importer/chr_extractor.gd`)
- **2BPP Decoding**:
  - Each 8x8 tile occupies 16 bytes in CHR-ROM: bytes `0..7` store bitplane 0 (LSB), bytes `8..15` store bitplane 1 (MSB), MSB-first (`bit = 7 - x`).
  - Pixel color index: `idx = ((p1 >> bit) & 1) << 1 | ((p0 >> bit) & 1)` yielding `0..3`.
  - Index `0` is universal background color for background tiles or full alpha (`#00000000`) for OAM sprites.
- **2C02 NTSC Master Palette**:
  - Uses an accurate 64-entry 2C02 NTSC color table (`0x00–0x3F`) to convert extracted 4-byte background sub-palettes (4 palettes x 4 colors) and 4-byte sprite sub-palettes into RGBA `Image` / `ImageTexture` atlases cached under `user://nes_data/`.

---

## 4. Gameplay Architecture & Core Specifications

### 4.1 16x16 Metatile Physics & Level Map (`src/game/level_map.gd`)
- **Metatile Composition**:
  - Every room is a grid of **16x16-pixel metatiles**, each defined by four 8x8 CHR tile indices (TL, TR, BL, BR), a 2-bit palette attribute (`0..3`), and a physical/interaction behavior type.
- **Collision & Terrain Flags**:
  - `AIR`: Passable empty space.
  - `SOLID`: Full 16x16 solid block (blocks horizontal/vertical movement, reflects bouncing stars/projectiles).
  - `ONE_WAY`: Passable from below and drop-through (`Down + A` or `Down` depending on context); solid from above.
  - `SLOPE_45_UP` / `SLOPE_45_DOWN` / `SLOPE_26_UP_L` / `SLOPE_26_UP_H` (and down mirrors): Continuous heightmap lookup `y = height_table[x & 0x0F]` enabling smooth walking, sliding, and rolling down hills.
  - `WATER`: Switches Kirby into swimming physics (`Swim` / `Water Gun` instead of Hover/Inhale).
  - `BREAKABLE_STAR`: Destroyable by Inhale, Star Spit, Slide, or Copy Abilities.
  - `BOMB_BLOCK` / `SPIKE_HAZARD` / `DOOR_TRANSITION`: Triggers room transitions, chain reactions, or damage with invulnerability frames.

### 4.2 Kirby Core Physics & State Machine (`src/game/kirby_controller.gd`)
All movement, collision, timers, and hitboxes execute deterministically inside `_physics_process(delta)` at **60 TPS** using fixed sub-pixel precision (`1/256` pixel or `float` quantized to authentic frame deltas):
- **Core States**:
  - `IDLE` / `WALK` / `RUN` (double-tap Left/Right to dash with dust puff and faster ground speed).
  - `CROUCH` & `SLIDE` (`Down + A` or `Down + B` launches a forward low-profile slide kick that breaks blocks and damages small enemies).
  - `JUMP` & `FALL` (variable jump height on releasing `A`; air control; fast-fall terminal velocity).
  - `HOVER` & `EXHALE` (pressing `Up` or `A` in midair inflates Kirby for infinite upward puffs; pressing `B` exhales an Air Puff projectile that pops blocks and weak enemies).
  - `SWIM` & `WATER_GUN` (in `WATER` metatiles: directional swimming + `B` fires short-range water squirt).
  - `INHALE` (holding `B` generates a forward suction cone pulling nearby enemies and star blocks into Kirby's mouth).
  - `MOUTH_FULL` (`Walk`/`Jump` with puffed cheeks; `B` fires a piercing **Star Spit** projectile; `Down` swallows to absorb an ability or discard a neutral enemy).
  - `DAMAGE_KNOCKBACK` & `DEFEAT` (6-HP health bar, brief hitstop + knockback + ~120-frame i-frame blink, drops current Copy Ability as a bouncing Ability Star on hit).

### 4.3 Copy Abilities (`src/game/abilities/`)
For the initial vertical slice, Kirby supports **4 flagship Copy Abilities** alongside `NONE` (Normal):
1. **Sword** (*Blade Knight / Sword Knight*):
   - Fast forward slash (`B`), multi-hit midair spin slash, and dash slash while running.
   - Cuts ropes/bushes and breaks blocks in front of Kirby.
2. **Fire** (*Hot Head / Flamer*):
   - Holding `B` emits a continuous short-to-mid-range jet of flame particles that ignites fuses/ice blocks and deals sustained damage.
3. **Spark** (*Sparky*):
   - Holding `B` surrounds Kirby in a 360° crackling electric barrier protecting from contact damage and striking adjacent enemies in all directions.
4. **Beam** (*Waddle Doo*):
   - Pressing `B` sweeps a 5-orb curved energy whip from overhead downward in front of Kirby, passing through thin walls and hitting mid-range targets.

---

## 5. 2A03 APU 5-Channel Audio Engine (`src/audio/`)

ReKirby emulates all **5 channels of the NES 2A03 APU** at 44,100 Hz via `AudioStreamGenerator` + `AudioStreamGeneratorPlayback`, stepped synchronously at 60 TPS:
1. **Pulse 1 & Pulse 2**: 4 hardware duty cycles (`12.5%`, `25%`, `50%`, `75%`), 11-bit timer period, hardware volume envelopes, and frequency sweep units.
2. **Triangle**: 32-step quantized triangle waveform, 11-bit timer period (one octave lower than pulse), and 60Hz/240Hz linear counter articulation.
3. **Noise**: 15-bit LFSR with both standard white-noise tap (bit 1) and short 93-step periodic metallic mode (bit 6), 16-entry NTSC noise period table, and envelope decay.
4. **DMC (Delta Modulation Channel)**: 1-bit DPCM sample playback using authentic 16-entry NTSC DMC rate table (`428` down to `54` CPU cycles per bit) and 7-bit delta counter (`0..127`), playing ROM-extracted percussion/bass samples and boss effects.
- **Gain Staging & Headroom**: Non-clipping normalized channel mix (`Pulse1 + Pulse2 + Triangle + Noise + DMC <= 1.0`) with priority-based SFX overrides on Pulse 1 / Noise / DMC so sound effects never stall or desync background music streams.

---

## 6. Software Architecture & Invariants

1. **Deterministic 60 TPS Loop**: Gameplay physics, enemy AI, camera scroll, MMC3 IRQ timing, and audio sequencing run strictly in `_physics_process(delta)` (`1.0 / 60.0`s).
2. **Strictly Typed GDScript**: Every variable, constant, parameter, and return type must declare explicit static types (`var hp: int = 6`, `func step(dt: float) -> void:`).
3. **Composition Over Inheritance**: Decoupled components (`KirbyController`, `AbilityComponent`, `EnemyActor`, `LevelMap`, `HUDRenderer`, `APUEngine`, `ROMImporter`) communicating through typed signals on `EventBus`.
4. **Cross-Platform Performance**: Target `gl_compatibility`, zero heavy post-processing, minimal allocations per physics tick so the game runs smoothly on both **Intel Core i5-2400 (Sandy Bridge, AVX-only)** and **Snapdragon 6 Gen 3 / Adreno 710 (Android)**.

### Target Autoload Singletons
- `EventBus` (`res://src/core/event_bus.gd`): Typed signal hub (HP changes, Copy Ability gained/dropped, score/lives updates, room transitions, boss phase, SFX requests).
- `ContentRegistry` (`res://src/core/content_registry.gd`): Holds validated, extracted CHR atlases, 16x16 metatile definitions, decompressed World 1 room maps, palettes, and APU sound tables from `user://nes_data/`.
- `InputManager` (`res://src/core/input_manager.gd`): Maps 8 NES inputs (`A`, `B`, `Select`, `Start`, `Up`, `Down`, `Left`, `Right`) across keyboard, standard gamepads, and Android multi-touch `VirtualGamepad`.

---

## 7. Directory Layout

### 7.1 Current Workspace State (Pre-Implementation Audit)
At this stage, no Godot project files or GDScript sources have been created yet. Currently present in `/sdcard/Documents/Codes/ReKirby`:
```text
ReKirby/
├── .gitignore                        # Excludes *.nes, rom/*.nes, rom/*.bin, .godot/, runtime dumps
├── Kirby's Adventure (USA) (Rev A).nes  # Local user ROM (git-ignored; move to rom/ during setup)
└── docs/
    ├── ARCHITECTURE.md               # ReKirby technical specification (this document)
    ├── MEMORY.md                     # Hardware constraints & ReKirby session log
    ├── STATUS.md                     # Vertical slice roadmap & progress tracker
    ├── SOUL.md                       # Assistant persona & rules (untouched)
    └── USER.md                       # User profile & hardware context (untouched)
```

### 7.2 Target Clean-Room Project Structure (`res://`)
```text
res://
├── project.godot                     # Godot 4 project config (256x240, 60 TPS, GL Compatibility, Nearest)
├── .gitignore                        # Excludes rom/*.nes, rom/*.bin, .godot/, user://, nes_data/
├── rom/                              # Git-ignored local ROM drop directory (empty in repo)
├── docs/
│   ├── ARCHITECTURE.md
│   ├── MEMORY.md
│   ├── STATUS.md
│   ├── SOUL.md
│   └── USER.md
├── src/
│   ├── main.gd                       # Root boot coordinator & Mandatory ROM Setup Guard
│   ├── main.tscn                     # Root scene (Playfield Viewport + Scanline HUD Split + VirtualGamepad)
│   ├── core/
│   │   ├── constants.gd              # NES/MMC3 hardware constants, enums, Copy Ability IDs, physics values
│   │   ├── event_bus.gd              # Global typed signal dispatcher
│   │   ├── content_registry.gd       # Runtime ROM asset & decompressed level repository
│   │   └── input_manager.gd          # Keyboard, gamepad & touch input mapper
│   ├── importer/
│   │   ├── rom_validator.gd          # iNES header, Mapper 4 check, SHA-256 / CRC32 verification
│   │   ├── mmc3_mapper.gd            # Virtual MMC3 PRG/CHR bank switcher & address resolver
│   │   ├── hal_decompressor.gd       # HAL Laboratory LZ77 / RLE bitstream decoder
│   │   ├── chr_extractor.gd          # 2BPP planar tile decoder & 2C02 NTSC palette atlas builder
│   │   └── rom_importer.gd           # Orchestrates full extraction into user://nes_data/
│   ├── game/
│   │   ├── level_map.gd              # 16x16 metatile grid, slopes, water, doors & room transitions
│   │   ├── kirby_controller.gd       # 60 TPS Kirby physics, inhale, swallow, hover, slide & combat
│   │   ├── abilities/
│   │   │   ├── ability_base.gd       # Typed Copy Ability interface
│   │   │   ├── ability_sword.gd      # Sword slash, air spin & dash slash
│   │   │   ├── ability_fire.gd       # Continuous flame jet
│   │   │   ├── ability_spark.gd      # 360-degree electric barrier
│   │   │   └── ability_beam.gd       # 5-orb curved energy whip
│   │   ├── entities/
│   │   │   ├── enemy_base.gd         # Inhaleable/damageable actor state machine
│   │   │   ├── star_projectile.gd    # Star Spit & dropped Ability Star physics
│   │   │   └── whispy_woods.gd       # World 1 Boss (air puffs, falling apples, HP phases)
│   │   ├── hud_renderer.gd           # Scanline Y=192 split HUD (HP, lives, score, ability card)
│   │   └── virtual_gamepad.gd        # Android/mobile multi-touch NES overlay
│   └── audio/
│       ├── apu_engine.gd             # 2A03 5-channel synthesizer (Pulse 1/2, Triangle, Noise, DMC)
│       └── music_player.gd           # PRG-ROM music/SFX sequence interpreter
└── tests/
    ├── test_runner.gd                # Headless verification harness (`godot --headless -s tests/test_runner.gd`)
    ├── test_importer.gd              # ROM validation, MMC3 banking, HAL LZ77/RLE & 2BPP tests
    ├── test_physics.gd               # 16x16 metatiles, slopes, hover, inhale & Copy Ability tests
    ├── test_audio.gd                 # 2A03 5-channel & DMC waveform/timing tests
    └── test_vertical_slice.gd        # World 1 Vegetable Valley room flow & Whispy Woods boss tests
```
