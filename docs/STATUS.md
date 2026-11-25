# Project Status (`docs/STATUS.md`)

> **Project**: **ReKirby** — Clean-Room Port of *Kirby's Adventure* (NES, 1993 — Mapper 4 MMC3)  
> **Engine**: Godot 4 (Strictly Typed GDScript, 60 TPS, GL Compatibility)

---

## Current Workspace Snapshot (Pre-Implementation)
- **Workspace State**: Documentation & repository hygiene phase only. No Godot project (`project.godot`), GDScript source (`src/`), or test suites (`tests/`) exist yet.
- **Completed So Far**:
  - [x] Audited workspace directory and verified local NTSC ROM header/checksums (`Kirby's Adventure (USA) (Rev A).nes`: 512 KB PRG-ROM, 256 KB CHR-ROM, Mapper 4 MMC3).
  - [x] Established clean-room `.gitignore` excluding `*.nes`, `rom/*.nes`, `rom/*.bin`, `.godot/`, and runtime extracted data.
  - [x] Rewrote `docs/ARCHITECTURE.md`, reset `docs/STATUS.md`, and cleaned `docs/MEMORY.md` for ReKirby while keeping `docs/SOUL.md` and `docs/USER.md` intact.

---

## Vertical Slice Roadmap

### Phase 0: Project Skeleton & Boot Guard (Pending)
- [ ] Create `rom/` directory and place local `.nes` ROM inside `rom/` (git-ignored).
- [ ] Initialize `project.godot` (256x240 base viewport, 60 TPS physics loop, Nearest texture filter, `gl_compatibility` renderer).
- [ ] Implement `src/core/constants.gd`, `src/core/event_bus.gd`, `src/core/content_registry.gd`, and `src/core/input_manager.gd`.
- [ ] Implement `src/main.gd` + `src/main.tscn` with Mandatory ROM Setup Guard & Missing ROM screen.
- [ ] Set up headless test harness (`tests/test_runner.gd`).

### Phase 1: ROM Extractor & Asset Importer (Pending)
- [ ] **ROM Validator (`src/importer/rom_validator.gd`)**: iNES header parsing, Mapper 4 MMC3 validation, SHA-256 / CRC32 verification.
- [ ] **MMC3 Virtual Mapper (`src/importer/mmc3_mapper.gd`)**: 8 KB PRG bank switching (`$8000-$FFFF`), 1 KB / 2 KB CHR bank switching (`R0–R5`), and H/V mirroring (`$A000`).
- [ ] **HAL Decompressor (`src/importer/hal_decompressor.gd`)**: Full HAL Laboratory LZ77/RLE decoder (opcodes `0..6`, extended 10-bit length mode, `0xFF` terminator).
- [ ] **CHR & Palette Extractor (`src/importer/chr_extractor.gd`)**: 2BPP planar tile decoding across 256 KB CHR-ROM + 2C02 NTSC 64-color master palette mapping into `user://nes_data/` PNG atlases.
- [ ] **Level & Table Extraction (`src/importer/rom_importer.gd`)**: Extract 16x16 metatile dictionaries, room layouts, OAM sprite definitions, and palette tables.
- [ ] **Verification (`tests/test_importer.gd`)**: Unit tests for HAL LZ77/RLE decompression vectors, 2BPP decoding, MMC3 bank mapping, and Missing ROM guard.

### Phase 2: Core Physics, Metatiles & Copy Abilities (Pending)
- [ ] **16x16 Metatile Physics (`src/game/level_map.gd`)**: Solid blocks, one-way platforms, 45° & 26.5° slopes, water zones, star blocks, spikes, and door transitions.
- [ ] **Kirby Core Controller (`src/game/kirby_controller.gd`)**: Walk, double-tap Run, Crouch, Slide, Jump, Hover + Air Puff, Swim + Water Gun, Inhale cone, Mouth-Full state, Star Spit, Swallow, and Damage/i-frames.
- [ ] **Copy Abilities (`src/game/abilities/`)**:
  - [ ] `Sword` (slash, air spin, dash slash)
  - [ ] `Fire` (continuous flame stream)
  - [ ] `Spark` (360° electric barrier)
  - [ ] `Beam` (5-orb sweeping curved whip)
- [ ] **Scanline IRQ Split HUD (`src/game/hud_renderer.gd`)**: Fixed `Y = 192..239` status bar with HP pips, lives, score, and active Copy Ability card portrait.
- [ ] **Mobile & Desktop Controls (`src/game/virtual_gamepad.gd`)**: Keyboard, gamepad, and Android touch overlay.
- [ ] **Verification (`tests/test_physics.gd`)**: Slope heightmap, inhale capture, star spit collisions, and all 4 Copy Ability hitboxes.

### Phase 3: 2A03 APU 5-Channel Audio Engine (Pending)
- [ ] **APU Synthesizer (`src/audio/apu_engine.gd`)**:
  - [ ] Pulse 1 & Pulse 2 (4 duty cycles, sweep, envelope)
  - [ ] Triangle (32-step quantized wave + linear counter)
  - [ ] Noise (15-bit LFSR standard & periodic modes)
  - [ ] DMC (1-bit DPCM sample channel with NTSC rate table)
- [ ] **PRG-ROM Music & SFX Interpreter (`src/audio/music_player.gd`)**: Extract and play authentic Kirby's Adventure BGM tracks & SFX with channel priority overrides.
- [ ] **Verification (`tests/test_audio.gd`)**: Non-clipping mix headroom, DPCM decoding, and 60 TPS audio stream stability.

### Phase 4: World 1 Vegetable Valley & Whispy Woods Boss Vertical Slice (Pending)
- [ ] **World 1 Enemies (`src/game/entities/enemy_base.gd`)**: Waddle Dee, Waddle Doo (Beam), Poppy Bros. Jr., Blade Knight (Sword), Hot Head (Fire), Sparky (Spark), Bronto Burt.
- [ ] **Stage Progression**: Vegetable Valley Stages 1–1 through 1–3 (including slopes, water section, breakable blocks, doors, Warp Star / Goal Game).
- [ ] **Boss Encounter (`src/game/entities/whispy_woods.gd`)**: Whispy Woods boss room (air puff attacks, falling apples to inhale/spit back, boss HP bar in scanline HUD, Star Rod / victory fanfare).
- [ ] **Target Platform Verification**:
  - [ ] Headless test runner (`godot --headless -s tests/test_runner.gd`) passing 100%.
  - [ ] Desktop verification on CachyOS (Intel i5-2400, GL Compatibility).
  - [ ] Android APK export & touch verification on Snapdragon 6 Gen 3.
