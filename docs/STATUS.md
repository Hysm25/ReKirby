# Project Status (`docs/STATUS.md`)

> **Project**: **ReKirby** — Clean-Room Port of *Kirby's Adventure* (NES, 1993 — Mapper 4 MMC3)  
> **Engine**: Godot 4 (Strictly Typed GDScript, 60 TPS, GL Compatibility)  
> **Overall Estimated ROM Fidelity**: **~56% / 100%** (Tracks A, B & C World 1 Metasprite/HUD/Title/Door-Graph parity complete; headless suite passing `374/374`)

---

## 1. ROM Fidelity Scorecard (~56% / 100%)

| Track | Scope | Est. Fidelity | Key Parity Gaps Observed |
| :--- | :--- | :---: | :--- |
| **Track A** | **Authentic OAM Sprite & Animation Bank Mapping** | **~75%** | `WorldExtractor` dynamically extracts Bank `24` -> script `0x1A` metasprite tables across all 27 World 1 actors + Bank `26..28` Kirby & Effect tables (`R0` CHR slots, `dx/dy`, `8x16` tiles, `attr` H/V flips & `SP0..SP3` palettes); remaining gaps are Copy Hat walking overlay compositing (`B26 $8EE6`), script wait-tick frame durations, and Whispy BG mouth/apple nametable patches. |
| **Track B** | **HUD, Font & Screen Layout Accuracy** | **~90%** | `WorldExtractor` extracts `B19 $AE7A` (Stage HUD), `B19 $AED5` (Hub HUD), `B19 $B3A4/$B3E1` (Lives packets), `B19 $B1F6/$B12C` (`SCORE`/`ENEMY`), `B19 $B313/$B338` (`4x5` Copy Cards), and `B61 $AB5C/$AA50/$ADB8` Title Screen (`32x30` + attributes + palettes); minor remaining gap is animated `R2` HP pip cycle (`122..125`) stepping continuously at 60Hz and World-Map `AFE1` sub-panel overlay. |
| **Track C** | **Room, Door, Scroll & Transition Fidelity** | **~85%** | `Constants.map_nes_collision_to_enum()` maps `0x20`/`0xA0` to `DOOR_TRANSITION`, `WorldExtractor` extracts `bgm_id`/`scroll_flag` + `trigger_mode` (`up_press`, `edge_top`, `edge_bottom`, `edge_right`), `Main` & `LevelMap` handle 21-room World 1 door traversal, Boss Room `30` arena camera lock, `Hub Room 0` (`456, 80`) victory return, pit defeat, and 8-frame door fade-in; minor remaining gap is Warp Star ride cutscene & Hub cleared-door star sprites. |
| **Track D** | **Full World 1–7 Extraction & Gameplay Completeness** | **~15%** | `WorldExtractor` only extracts World 1 (21 rooms, 9 tilesets) and implements 4 of 24+ Copy Abilities; Worlds 2–7 (Ice Cream Island through Rainbow Resort), mid-bosses, museum/arena/sub-game rooms, Stage `1-4`, Save Slot select, Game Over, and Ending sequences are unimplemented. |
| **Track E** | **2A03 APU & DPCM Audio Accuracy** | **~30%** | Bank 29 bytecode decoder parses core tracks/SFX without continuous whine, but remaining duty/sweep/vibrato/envelope nuances, authentic DPCM channel gain/rate quirks, and complete gameplay SFX trigger bindings (`inhale`, `spit`, `swallow`, `door`, `hurt`, `pause`, `boss`) need Bank 29 parity auditing. |

---

## 2. Implemented Engineering Baseline (Structural Foundation)
The following clean-room engine infrastructure is built and verified (`tests/test_runner.gd`: `374/374` passing in headless mode):
- [x] **Mandatory ROM Ingestion & Clean-Room Boundary**: iNES Mapper 4 MMC3 validation (`src/importer/rom_validator.gd`), virtual MMC3 banking (`mmc3_mapper.gd`), HAL LZ77/RLE decompression (`hal_decompressor.gd`), 2BPP CHR decoding (`chr_extractor.gd`), World 1 + Metasprite PRG table extractor (`world_extractor.gd`), Bank 29 audio extractor (`audio_extractor.gd`), and Missing ROM boot guard (`src/main.gd`).
- [x] **Core Simulation & Controls**: 60 TPS `KirbyController`, 16x16 `LevelMap` collision/slope heightmaps, 4 baseline Copy Abilities (`Sword`, `Fire`, `Spark`, `Beam`), outer-margin `VirtualGamepad`, and baseline `TitleScreen` / `HUDRenderer` / `APUEngine` / `MusicPlayer`.

---

## 3. Prioritized Fidelity Backlog Queue (Continuous Parity Loop)

### Fidelity Milestone 1 — PRG-ROM OAM Metasprite, Animation & Dynamic CHR Bank Tables (Completed)
- [x] **Audit PRG-ROM OAM & CHR Bank Tables in `rom/*.nes`**: Located Bank `62` OAM builders (`$DA89`, `$DCEC`, `$DDAA`, `$DDA3`, `$DDD9`), `Bank 24 ($A0A7/$A117/$A187)` actor script index, HAL VM `0x1A` metasprite table opcodes (`Bank 48..58`), and Kirby / Effect R0-prefixed metasprite pointer tables (`Bank 26..28`).
- [x] **Extract Metasprites via Importer (`src/importer/world_extractor.gd`)**: Added `_parse_oam_frame_table()`, `_extract_actor_metasprite_entry()`, and `extract_metasprite_catalog()` extracting all 27 World 1 actors + 8 Kirby pose/ability tables + 5 Effect tables dynamically into `user://nes_data/world1_data.json` (`EXTRACTION_FORMAT_VERSION = 5`).
- [x] **Wire Multi-Tile OAM & `R0..R5` Bank Switching**: Added `ContentRegistry.build_rom_metasprite()` + `get_room_sprite_palettes()` handling `1..16` hardware `8x16` sprites per frame, dynamic `R0`/`R1`/`common_odd` bank routing, `(dx, dy)` alignment, OAM priority, H/V flips, and `SP0..SP3` palettes across `KirbyController`, `EnemyBase`, `StarProjectile`, `TitleScreen`, and `HUDRenderer` (`338/338` tests passing).

### Fidelity Milestone 2 — Track B: Pixel-Exact HUD Nametable, Card & MMC3 Scanline Layout Parity (Completed)
- [x] **Extract Authentic HUD Nametable & Border/Card Layouts**: Extracted Bank `19` HUD HAL nametables (`$AE7A` Stage, `$AED5` Hub), Lives PPU packets (`$B3A4`, `$B3E1`), `SCORE`/`ENEMY` labels (`$B1F6`, `$B12C`), `4x5` Copy Ability card tables (`$B313`/`$B338` -> CHR `64..75`), `0xFF` attribute fill (`$ADF2`), animated `R2` banks (`122..125`), and Bank `61` Title Screen (`$AB5C`, `$AA50`, `$ADB8`) dynamically (`EXTRACTION_FORMAT_VERSION = 6`).
- [x] **Refactor `HUDRenderer` & `TitleScreen`**: `HUDRenderer` renders the `32x7` ROM nametable cropped cleanly into `256x48` (`Y=192..239`) with room `BG_3` palettes, `4x5` ability cards (`NONE/SWORD/FIRE/SPARK/BEAM`), `6` HP pips (`0x1A..0x1C` / `0x81, 0x98, 0x81`), `SCORE`/`ENEMY`, and `1UP` lives box; `TitleScreen` renders the `256x240` `B61 $AB5C` attribute-colored nametable (`357/357` tests passing).

### Fidelity Milestone 3 — Track C: World 1 Door, Camera Scroll-Lock, Spawn & Transition Fidelity (Completed)
- [x] **Audit PRG-ROM Room Headers, Scroll Locks & Door Records**: Audited all 21 World 1 rooms (`R0`, `R24`, `R30`, `R43..R60`) and 33 doors; fixed `0x20`/`0xA0` `DOOR_TRANSITION` collision mapping (`src/core/constants.gd`), extracted `bgm_id` (`raw[6]`), `scroll_flag` (`raw[7]`), and `trigger_mode` (`edge_top`, `edge_bottom`, `edge_right`, `up_press`) in `WorldExtractor`.
- [x] **Eliminate Transition Softlocks & Spawn Misplacements**: Added `LevelMap.find_edge_door_at_kirby()` & `compute_door_spawn_pixel()`, fixed Boss Room `30` door spawn & arena camera lock (`pos.y >= 384`), fixed Goal Star Rod return spawn into `Hub Room 0` (`456, 80`), wired room BGM switching, pit-fall defeat, and 8-frame fade-in transitions in `Main` (`374/374` tests passing).

### Fidelity Milestone 4 — Track E: Bank 29 2A03 APU Envelope, Sweep, Pitch & Gameplay SFX Parity (**NEXT / IN QUEUE**)
- [ ] **Audit Bank 29 (`0x1D`) Sound Driver Opcodes**: Verify hardware frequency sweep opcodes, arpeggio/vibrato/pitch bend, noise/DPCM trigger timing, triangle linear counter muting, and SFX priority behavior against PRG-ROM driver tables.
- [ ] **Wire Complete Gameplay SFX Triggers**: Connect `EventBus.sfx_requested` cleanly across jump, hover puff, inhale loop, star spit, swallow, ability gain/drop, slide, door warp, damage, enemy defeat, 1-UP, and boss defeat fanfare.

### Fidelity Milestone 5 — Track D: Full World 1–7 Extraction, Remaining Abilities, Mid-Bosses & Save/Ending Loops
- [ ] **Generalize `WorldExtractor` to Worlds 1–7**: Extract all World 1–7 hubs, stages, animated tile swaps, sub-palettes, doors, and actor spawn tables (`Vegetable Valley`, `Ice Cream Island`, `Butter Building`, `Grape Garden`, `Yogurt Yard`, `Orange Ocean`, `Rainbow Resort`).
- [ ] **Implement Remaining Copy Abilities, Mid-Bosses & Meta Loops**: Add remaining Copy Abilities, mid-boss encounters, Arena/Museum/Sub-Game rooms, 3-slot Battery Save / Game Over flow, Pause Screen ability description display, and Credits/Ending sequence.
