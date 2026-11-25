# Project Status (`docs/STATUS.md`)

> **Project**: **ReKirby** — Clean-Room Port of *Kirby's Adventure* (NES, 1993 — Mapper 4 MMC3)  
> **Engine**: Godot 4 (Strictly Typed GDScript, 60 TPS, GL Compatibility)

---

## Current Workspace Snapshot (Phase 3 Complete — 2A03 APU 5-Channel Audio & PRG-ROM Music/SFX)
- **Workspace State**: Godot 4.7.1 project skeleton (`project.godot`), Core Autoloads (`src/core/`), full ROM, World 1, and Audio PRG-ROM Extraction Pipeline (`src/importer/` including `AudioExtractor`), Mandatory ROM Setup Guard + Playable World 1 Room Boot (`src/main.gd`, `src/main.tscn`), Phase 2 `LevelMap`, `KirbyController`, Copy Abilities (`Sword`, `Fire`, `Spark`, `Beam`), Scanline IRQ Split `HUDRenderer`, and `VirtualGamepad` (`src/game/`), Phase 3 2A03 5-channel `APUEngine` & `MusicPlayer` (`src/audio/`), and headless test suite (`tests/test_runner.gd`, `tests/test_importer.gd`, `tests/test_physics.gd`, `tests/test_audio.gd`) implemented and passing 100% (`222/222`).
- **Completed So Far**:
  - [x] Audited workspace directory, relocated local ROM into git-ignored `rom/`, and verified `rom/*.nes` exclusion.
  - [x] Established clean-room `.gitignore` and `AGENTS.md` execution blueprint.
  - [x] Rewrote `docs/ARCHITECTURE.md`, `docs/STATUS.md`, and `docs/MEMORY.md` for ReKirby while keeping `docs/SOUL.md` and `docs/USER.md` untouched.

---

## Vertical Slice Roadmap

### Phase 0: Project Skeleton & Boot Guard (Completed)
- [x] Create `rom/` directory with `rom/.gitkeep` and place local `.nes` ROM inside `rom/` (git-ignored).
- [x] Initialize `project.godot` (256x240 base viewport, `canvas_items`/`expand`, 60 TPS physics loop, Nearest texture filter, `gl_compatibility` renderer, strict GDScript warnings enabled).
- [x] Implement `src/core/constants.gd`, `src/core/event_bus.gd`, `src/core/content_registry.gd`, and `src/core/input_manager.gd`.
- [x] Implement `src/main.gd` + `src/main.tscn` with Mandatory ROM Setup Guard & `256x240` Missing ROM setup screen.
- [x] Set up headless test harness (`tests/test_runner.gd`).

### Phase 1: ROM Extractor & Asset Importer (Completed)
- [x] **ROM Validator (`src/importer/rom_validator.gd`)**: iNES header parsing, Mapper 4 MMC3 validation, CRC32 & SHA-256 verification.
- [x] **MMC3 Virtual Mapper (`src/importer/mmc3_mapper.gd`)**: 8 KB PRG bank switching (`$8000-$FFFF`), 1 KB / 2 KB CHR bank switching (`R0–R5`), H/V mirroring (`$A000`), and scanline IRQ state.
- [x] **HAL Decompressor (`src/importer/hal_decompressor.gd`)**: Full HAL Laboratory LZ77/RLE decoder (opcodes `0..6` including bit-reversed `5` and backward `6`, extended 10-bit length mode, `0xFF` terminator, strict `MAX_ITERATIONS` & bounds checks).
- [x] **CHR & Palette Extractor (`src/importer/chr_extractor.gd`)**: 2BPP planar tile decoding across 256 x 1KB CHR-ROM banks + 2C02 NTSC 64-color master palette mapping into `user://nes_data/` PNG atlases (`32` x `512x64` sheets).
- [x] **ROM Importer (`src/importer/rom_importer.gd`)**: Scans `rom/` (and root fallback), validates ROM, extracts CHR sheets, World 1 tables, and palettes into `user://nes_data/`, and populates `ContentRegistry`.
- [x] **Level & Table Extraction (`src/importer/world_extractor.gd`)**: Dynamic PRG-ROM extraction via `MMC3Mapper` + `HALDecompressor` of 16x16 metatile dictionaries (tiles, 2-bit palettes, NES collision shapes), all 21 World 1 rooms (`R000` Hub, Stages 1-1..1-4 `R043..R060`, Whispy Woods Boss `R030`, Museum `R024`), BG/Sprite subpalettes, 1KB CHR bank bindings, doors, and entity spawns cached to `user://nes_data/world1_data.json`.
- [x] **Verification (`tests/test_importer.gd`)**: 91 assertions passing (`0` failed) covering HAL LZ77/RLE opcodes, 2BPP decoding, MMC3 bank mapping, collision mapping, `InputManager` 60 TPS/SOCD, `ContentRegistry` guard, live ROM + World 1 extraction, and `user://nes_data/` disk reload.

### Phase 2: Core Physics, Metatiles & Copy Abilities (Completed)
- [x] **16x16 Metatile Physics (`src/game/level_map.gd`)**: Solid blocks, one-way platforms, 45° & 26.5° slopes, water zones, star blocks, spikes, and door transitions.
- [x] **Kirby Core Controller (`src/game/kirby_controller.gd`)**: Walk, double-tap Run, Crouch, Slide, Jump, Hover + Air Puff, Swim + Water Gun, Inhale cone, Mouth-Full state, Star Spit, Swallow, Ability drop (`SELECT`), and Damage/i-frames (wired into `src/main.gd`).
- [x] **Copy Abilities (`src/game/abilities/`)**:
  - [x] `Sword` (slash, air spin, dash slash)
  - [x] `Fire` (continuous flame stream)
  - [x] `Spark` (360° electric barrier)
  - [x] `Beam` (5-orb sweeping curved whip)
- [x] **Scanline IRQ Split HUD (`src/game/hud_renderer.gd`)**: Fixed `Y = 192..239` status bar with HP pips, lives, score, boss HP, and active Copy Ability card portrait via ROM CHR + Bank 56 palettes.
- [x] **Mobile & Desktop Controls (`src/game/virtual_gamepad.gd`)**: Keyboard, gamepad, and Android touch overlay.
- [x] **Verification (`tests/test_physics.gd`)**: Slope heightmap, inhale capture, star spit collisions, HUD/touch routing, and all 4 Copy Ability hitboxes (`88/88` passing; `183/183` total).

### Phase 3: 2A03 APU 5-Channel Audio Engine (Completed)
- [x] **APU Synthesizer (`src/audio/apu_engine.gd`)**:
  - [x] Pulse 1 & Pulse 2 (4 duty cycles, sweep, envelope)
  - [x] Triangle (32-step quantized wave + linear counter)
  - [x] Noise (15-bit LFSR standard & periodic modes)
  - [x] DMC (1-bit DPCM sample channel with NTSC rate table)
- [x] **PRG-ROM Music & SFX Interpreter (`src/audio/music_player.gd`)**: Extract via `AudioExtractor` (`src/importer/audio_extractor.gd`) and play authentic Kirby's Adventure BGM tracks & SFX with channel priority overrides.
- [x] **Verification (`tests/test_audio.gd`)**: Non-clipping mix headroom, DPCM decoding, 93-step periodic noise, and 60 TPS audio stream stability (`39/39` passing; `222/222` total).

### Phase 4: World 1 Vegetable Valley & Whispy Woods Boss Vertical Slice (Pending)
- [ ] **World 1 Enemies (`src/game/entities/enemy_base.gd`)**: Waddle Dee, Waddle Doo (Beam), Poppy Bros. Jr., Blade Knight (Sword), Hot Head (Fire), Sparky (Spark), Bronto Burt.
- [ ] **Stage Progression**: Vegetable Valley Stages 1–1 through 1–3 (including slopes, water section, breakable blocks, doors, Warp Star / Goal Game).
- [ ] **Boss Encounter (`src/game/entities/whispy_woods.gd`)**: Whispy Woods boss room (air puff attacks, falling apples to inhale/spit back, boss HP bar in scanline HUD, Star Rod / victory fanfare).
- [ ] **Target Platform Verification**:
  - [ ] Headless test runner (`godot --headless -s tests/test_runner.gd`) passing 100%.
  - [ ] Desktop verification on CachyOS (Intel i5-2400, GL Compatibility).
  - [ ] Android APK export & touch verification on Snapdragon 6 Gen 3.
