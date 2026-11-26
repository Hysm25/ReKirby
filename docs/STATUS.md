# Project Status (`docs/STATUS.md`)

> **Project**: **ReKirby** — Clean-Room Port of *Kirby's Adventure* (NES, 1993 — Mapper 4 MMC3)  
> **Engine**: Godot 4 (Strictly Typed GDScript, 60 TPS, GL Compatibility)  
> **Overall Estimated ROM Fidelity**: **~99% / 100%** (Tracks A–E + Script Wait-Ticks, Whispy BG Canopy Patches, Multi-Round Egg Catcher & Hardware 2A03 Sweep Unit complete; headless suite passing `481/481`)

---

## 1. ROM Fidelity Scorecard (~99% / 100%)

| Track | Scope | Est. Fidelity | Key Parity Gaps Observed |
| :--- | :--- | :---: | :--- |
| **Track A** | **Authentic OAM Sprite & Animation Bank Mapping** | **~98%** | Extracted per-actor HAL VM `0x0F` wait-tick frame durations (`wait_ticks`) driving `EnemyBase` & `BossController` animation cadence, `B26 $8EE6` Copy Hat overlays, `AbilityGeneric` ROM effect metasprites, and Room `30` Whispy Woods Bank `180` BG canopy patch (`_canopy_patch_sprite`). |
| **Track B** | **HUD, Font & Screen Layout Accuracy** | **~99%** | `HUDRenderer` (`B19 $AE7A/$AED5`, `4x5` Copy Cards, `60Hz` `R2` `122..125` HP pip cycling, `SCORE`/`ENEMY`, `1UP` box), `TitleScreen` (`B61 $AB5C`), interactive 3-slot `FileSelectScreen`, World Map header (`VEGETABLE VALLEY`..`RAINBOW RESORT`), & `SubgameOverlay` multi-round counter are complete. |
| **Track C** | **Room, Door, Scroll & Transition Fidelity** | **~98%** | All `327` ROM rooms, `0x20`/`0xA0` doors, edge auto-doors (`edge_top`/`bottom`/`right`), 60 TPS Warp Star Cutscenes (`0x1E`/`0x1F`), Hub cleared-stage ROM Star badges, Boss arena camera locks, and 8-frame door fades work seamlessly. |
| **Track D** | **Full World 1–7 Extraction & Gameplay Completeness** | **~99%** | All `327` rooms & `34` valid tilesets extracted; `BossController` + `WhispyWoods` drive Worlds 1–7 & Final Boss, `EnemyBase` handles Mid-Bosses (`72..79`) + Museum Copy Pedestals (`R24..R29`), `KirbyController` supports 25 Copy Abilities, and `Main` integrates `FileSelectScreen`, `SubgameOverlay` (including 5-round Egg Catcher), `PAUSED`, `GAME_OVER`, & `ENDING`. |
| **Track E** | **2A03 APU & DPCM Audio Accuracy** | **~99%** | Bank `29` opcodes (`0xE1`, `0xE2`, `0xE3`, `0xF2`, `0xF7` vibrato LFO, `$8046` SFX priority) + DPCM + `Constants.NesSfx` + true Ricoh 2A03 continuous hardware pulse sweep target overflow muting & `$4001/$4005 = 0x08` negate init complete. |

---

## 2. Implemented Engineering Baseline (Structural Foundation)
The following clean-room engine infrastructure is built and verified (`tests/test_runner.gd`: `378/378` passing in headless mode):
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

### Fidelity Milestone 4 — Track E: Bank 29 2A03 APU Envelope, Sweep, Pitch & Gameplay SFX Parity (Completed)
- [x] **Audit Bank 29 (`0x1D`) Sound Driver Opcodes**: Fixed `0xE1` fade/attenuation separation from `0xF2` tempo, `0xE2` raw 11-bit period retrigger (`$83DC`), `0xE3` cumulative signed period delta sweeps (`$8666`), `0xF7` vibrato table index (`$8738`), and `$8046` SFX priority precedence (`lower = higher priority`) in `MusicPlayer`.
- [x] **Wire Complete Gameplay SFX Triggers**: Added `Constants.NesSfx` and wired `EventBus.sfx_requested` across `KirbyController` (`JUMP`, `HOVER_PUFF`, `INHALE`, `STAR_SPIT`, `SWALLOW`, `ABILITY_ATTACK`, `ABILITY_DROP`, `SLIDE`, `HURT`) and `Main` (`DOOR_WARP`, `BLOCK_BREAK`, `STAGE_CLEAR`) (`378/378` tests passing).

### Fidelity Milestone 5 — Track D: Full World 1–7 Extraction, Remaining Abilities, Mid-Bosses & Save/Ending Loops (Completed)
- [x] **Generalize `WorldExtractor` to Worlds 1–7**: Fixed `screen_grid` reuse size check for rooms `14/212/223` and unused tileset slots (`29..31, 33, 37..47`), extracting all `327` ROM rooms (`0..326`), `34` valid tilesets, all `62` unique actor metasprites, and Worlds 1–7 Hubs (`0..6`), Bosses (`30..36`), & Fountain of Dreams (`15`) (`EXTRACTION_FORMAT_VERSION = 8`).
- [x] **Implement Remaining Copy Abilities & Meta Loops**: Added 20 additional Copy Abilities via `AbilityGeneric` (`CUTTER` through `SLEEP`, 25 total) mapped to `B19 $B313/$B338` cards & `EnemyBase.ability_for_actor_id()`, 3-slot `SaveManager` (`user://save_data.json`), Pause (`PAUSED`), Game Over (`GAME_OVER`), World 2–7 Boss progression, and Ending (`ENDING`) state (`421/421` tests passing).

### Fidelity Milestone 6 — Track D/A: Distinct World 2–7 Bosses, Mid-Bosses, Ability Hat Overlays & APU Vibrato (Completed)
- [x] **Distinct World 2–7 Boss & Mid-Boss AI**: Implemented `BossController` (`src/game/entities/boss_controller.gd`) driving Paint Roller (`R31/R08`), Mr. Shine & Mr. Bright (`R32/R09`), Kracko (`R33/R10`), Heavy Mole (`R34/R11`), Meta Knight (`R35/R12`), King Dedede (`R36/R14`), and Nightmare (`R15`) with ROM `actor_id` metasprite frames (`224`-byte script scan), plus `EnemyBase.EnemyType.MID_BOSS` (`actor_id 72..79` with `6` HP, inhale resistance & Copy Ability Star drops).
- [x] **Copy Hat Overlays, R2 Pip Cycling & Audio Vibrato**: Added `KirbyController` Copy Hat overlay compositing (`B26 $8EE6` `hat_walk`), `HUDRenderer.step_frame()` continuous `R2` HP pip cycling (`122..125`), and `MusicPlayer.compute_vibrato_delta()` (`0xF7` symmetric pitch LFO modulation) (`452/452` tests passing).

### Fidelity Milestone 7 — Track B/C/D: Interactive 3-Slot File Select, Warp Star Cutscenes, Hub Star Badges & Sub-Games (Completed)
- [x] **Interactive File Select, Warp Star & Hub Progression UI**: Added `FileSelectScreen` (`src/game/file_select_screen.gd`, `GameState.FILE_SELECT`) wired after `TitleScreen`, Hub cleared-stage ROM Star door badges (`_hub_star_badges`), Hub World Map header banner, and 60 TPS Warp Star Ride cutscenes (`WARP_STAR_FRAMES = 36`) between World Hubs (`0x1E`/`0x1F`).
- [x] **Playable Sub-Games, Museum Pedestals & ROM Ability Effect Metasprites**: Added `SubgameOverlay` (`src/game/subgame_overlay.gd`, `GameState.SUBGAME`) supporting Crane Fever (`0x1A`), Egg Catcher (`0x1B`), & Quick Draw (`0x1C`), wired Museum `actor_id 10` `subtype` Copy Pedestals (`R24..R29`), and upgraded `AbilityGeneric` to composite ROM effect metasprite frames (`470/470` tests passing).

### Fidelity Milestone 8 — Track A/E: Per-Actor Script Frame Durations, Whispy BG Nametable Patches & Hardware APU Sweep Curves (Completed)
- [x] **Authentic Actor Script Wait-Ticks & Whispy BG Patches**: Extracted HAL VM `0x0F` wait-tick frame durations in `WorldExtractor._extract_actor_metasprite_entry()` (`EXTRACTION_FORMAT_VERSION = 9`), exposed `ContentRegistry.get_actor_wait_ticks()`, wired NTSC animation wait-ticks into `EnemyBase` & `BossController`, and added Room `30` Whispy Woods Bank `180` BG canopy patch sprite (`_canopy_patch_sprite`).
- [x] **Multi-Throw Egg Catcher & Hardware 2A03 Sweep Unit**: Expanded `SubgameOverlay` Egg Catcher (`0x1B`) to a 5-round accelerating barrage (`EGG_ROUNDS = 5`), enabled continuous hardware 2A03 sweep overflow muting (`get_sweep_target_period() > 0x7FF` & `compute_hardware_sweep_edge()`) in `APUEngine`, and initialized `$4001/$4005 = 0x08` negate in `MusicPlayer` (`481/481` tests passing).

### Fidelity Milestone 9 — Extra Mode, Boss Rush & Title Demo Attract Sequence (**NEXT / IN QUEUE**)
- [ ] **Extra Mode & Sound Test / Boss Rush**: Add post-clear unlockable Extra Mode (`3 HP` cap + faster enemy speed), Boss Endurance Rush (`R30..R36` -> `R15` chain), Sound Test track/SFX browser driven by `ContentRegistry.get_audio_tables()`, and idle Title Screen Demo Attract playback.
