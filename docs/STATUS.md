# Project Status (`docs/STATUS.md`)

> **Project**: **ReKirby** — Clean-Room Port of *Kirby's Adventure* (NES, 1993 — Mapper 4 MMC3)  
> **Engine**: Godot 4 (Strictly Typed GDScript, 60 TPS, GL Compatibility)  
> **Overall Estimated ROM Fidelity**: **~20% / 100%** (Headless vertical-slice prototype runs cleanly at `320/320`, while true 1:1 NES OAM, HUD, scroll/door flow, full 7-world content, and Bank 29 audio parity require systematic ROM reverse-engineering & parity milestones)

---

## 1. ROM Fidelity Scorecard (~20% / 100%)

| Track | Scope | Est. Fidelity | Key Parity Gaps Observed |
| :--- | :--- | :---: | :--- |
| **Track A** | **Authentic OAM Sprite & Animation Bank Mapping** | **~15%** | Currently relies on manually indexed `8x16` tile pairs (`KirbyController`, `EnemyBase`, `WhispyWoods`, `StarProjectile`); lacks PRG-ROM metasprite layout tables, frame-duration tables, and dynamic MMC3 `R0..R5` 1KB/2KB CHR bank swaps per animation frame/entity/HUD state. |
| **Track B** | **HUD, Font & Screen Layout Accuracy** | **~30%** | Bank `254` font transparency & `VirtualGamepad` outer-margin bounds are working, but exact CHR HUD border tiles, glyph spacing, life/HP/ability card tilemap assembly, and `Y=192..239` MMC3 IRQ split layout still deviate from the NES PPU nametable/OAM screen. |
| **Track C** | **Room, Door, Scroll & Transition Fidelity** | **~25%** | Boots into synthetic `TitleScreen -> Room 43` and supports basic `Room 43 -> 44` / `47` / `53` / `30` loads, but lacks full PRG-ROM door/warp metadata fidelity, camera scroll-lock strips, fade/warp-star/boss-door transitions, and verified Hub `Room 0` -> Stages `1-1..1-4` -> `Whispy Woods` loop without softlocks or spawn misplacement. |
| **Track D** | **Full World 1–7 Extraction & Gameplay Completeness** | **~15%** | `WorldExtractor` only extracts World 1 (21 rooms, 9 tilesets) and implements 4 of 24+ Copy Abilities; Worlds 2–7 (Ice Cream Island through Rainbow Resort), mid-bosses, museum/arena/sub-game rooms, Stage `1-4`, Save Slot select, Game Over, and Ending sequences are unimplemented. |
| **Track E** | **2A03 APU & DPCM Audio Accuracy** | **~30%** | Bank 29 bytecode decoder parses core tracks/SFX without continuous whine, but remaining duty/sweep/vibrato/envelope nuances, authentic DPCM channel gain/rate quirks, and complete gameplay SFX trigger bindings (`inhale`, `spit`, `swallow`, `door`, `hurt`, `pause`, `boss`) need Bank 29 parity auditing. |

---

## 2. Implemented Engineering Baseline (Structural Foundation)
The following clean-room engine infrastructure is built and verified (`tests/test_runner.gd`: `320/320` passing in headless mode):
- [x] **Mandatory ROM Ingestion & Clean-Room Boundary**: iNES Mapper 4 MMC3 validation (`src/importer/rom_validator.gd`), virtual MMC3 banking (`mmc3_mapper.gd`), HAL LZ77/RLE decompression (`hal_decompressor.gd`), 2BPP CHR decoding (`chr_extractor.gd`), World 1 PRG table extractor (`world_extractor.gd`), Bank 29 audio extractor (`audio_extractor.gd`), and Missing ROM boot guard (`src/main.gd`).
- [x] **Core Simulation & Controls**: 60 TPS `KirbyController`, 16x16 `LevelMap` collision/slope heightmaps, 4 baseline Copy Abilities (`Sword`, `Fire`, `Spark`, `Beam`), outer-margin `VirtualGamepad`, and baseline `TitleScreen` / `HUDRenderer` / `APUEngine` / `MusicPlayer`.

---

## 3. Prioritized Fidelity Backlog Queue (Continuous Parity Loop)

### Fidelity Milestone 1 — PRG-ROM OAM Metasprite, Animation & Dynamic CHR Bank Tables (**NEXT / IN QUEUE**)
- [ ] **Audit PRG-ROM OAM & CHR Bank Tables in `rom/*.nes`**: Locate and document authentic sprite metasprite definitions (relative `(dx, dy)` offsets, 8x16 tile indices, attribute/palette bits, H/V flip bits), animation frame pointer/duration tables, and dynamic MMC3 `R0..R5` 1KB/2KB CHR bank assignments for Kirby, copy hats/abilities, World 1 enemies (`Waddle Dee`, `Waddle Doo`, `Poppy Bros. Jr.`, `Blade Knight`, `Hot Head`, `Sparky`, `Bronto Burt`), projectiles, `Whispy Woods`, and HUD card portraits.
- [ ] **Extract Metasprites via Importer (`src/importer/world_extractor.gd`)**: Export extracted metasprite & animation frame JSON definitions dynamically at runtime into `user://nes_data/` (zero hardcoded tile guesses in `src/`).
- [ ] **Wire Multi-Tile OAM & `R0..R5` Bank Switching**: Replace guessed `Vector2i` pairs in `ContentRegistry`, `KirbyController`, `EnemyBase`, `WhispyWoods`, `StarProjectile`, and `HUDRenderer` with ROM-driven multi-tile OAM frame composition and dynamic CHR bank slot lookup; add regression assertions verifying extracted metasprite counts, bank bindings, and multi-tile bounds.

### Fidelity Milestone 2 — Track B: Pixel-Exact HUD Nametable, Card & MMC3 Scanline Layout Parity
- [ ] **Extract Authentic HUD Nametable & Border/Card Layouts**: Inspect PRG-ROM HUD tilemap/attribute data, CHR bank bindings (`R0..R5` during `Y=192..239` IRQ split), Copy Ability card art (`Bank` + `16x24`/`32x24` card frame), animated HP pips, digit/lives alignment, and Title Screen PPU nametable/OAM composition from `rom/*.nes`.
- [ ] **Refactor `HUDRenderer` & `TitleScreen`**: Render HUD frame, HP pips, lives counter, score digits, boss gauge, and Copy Ability portrait card pixel-for-pixel matching authentic NES layout (`256x48` at `Y=192..239`).

### Fidelity Milestone 3 — Track C: World 1 Door, Camera Scroll-Lock, Spawn & Transition Fidelity
- [ ] **Audit PRG-ROM Room Headers, Scroll Locks & Door Records**: Verify 5-byte door destination coordinates, entrance spawn offsets, room camera lock strips, screen-size limits, fade-out/fade-in PPU palette transitions, Warp Star rides, and World 1 Hub (`Room 0`) -> Stage doors `1-1` (`R43..R46`), `1-2` (`R47..R52`), `1-3` (`R53..R56`), `1-4` (`R57..R60`), Museum (`R24`), and `Whispy Woods` (`R30`) boss transitions.
- [ ] **Eliminate Transition Softlocks & Spawn Misplacements**: Fix `Main`, `LevelMap`, and `KirbyController` door entry, underwater room spawns, boss lock camera bounds, and stage-clear Goal Star Rod return flow to Hub `Room 0` with automated room-graph reachability tests.

### Fidelity Milestone 4 — Track E: Bank 29 2A03 APU Envelope, Sweep, Pitch & Gameplay SFX Parity
- [ ] **Audit Bank 29 (`0x1D`) Sound Driver Opcodes**: Verify hardware frequency sweep opcodes, arpeggio/vibrato/pitch bend, noise/DPCM trigger timing, triangle linear counter muting, and SFX priority behavior against PRG-ROM driver tables.
- [ ] **Wire Complete Gameplay SFX Triggers**: Connect `EventBus.sfx_requested` cleanly across jump, hover puff, inhale loop, star spit, swallow, ability gain/drop, slide, door warp, damage, enemy defeat, 1-UP, and boss defeat fanfare.

### Fidelity Milestone 5 — Track D: Full World 1–7 Extraction, Remaining Abilities, Mid-Bosses & Save/Ending Loops
- [ ] **Generalize `WorldExtractor` to Worlds 1–7**: Extract all World 1–7 hubs, stages, animated tile swaps, sub-palettes, doors, and actor spawn tables (`Vegetable Valley`, `Ice Cream Island`, `Butter Building`, `Grape Garden`, `Yogurt Yard`, `Orange Ocean`, `Rainbow Resort`).
- [ ] **Implement Remaining Copy Abilities, Mid-Bosses & Meta Loops**: Add remaining Copy Abilities, mid-boss encounters, Arena/Museum/Sub-Game rooms, 3-slot Battery Save / Game Over flow, Pause Screen ability description display, and Credits/Ending sequence.
