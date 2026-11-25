---
tags: [ai-context, memory]
updated: 2026-11-25
---

# Persistent Memory & Quirks (`docs/MEMORY.md`)

## 1. Project Context & Objectives
- **Project**: **ReKirby** — Clean-room PC & Android port of **Kirby's Adventure** (NES / Famicom, 1993, Mapper 4 MMC3) built in **Godot 4 (Strictly Typed GDScript)**.
- **Simulation Target**: Frame-accurate NTSC 60Hz simulation (`_physics_process` locked at 60 TPS, `256x240` native NES resolution, nearest-neighbor filtering, `gl_compatibility` renderer).
- **Legal Boundary & Mandatory ROM Ingestion**:
  - **Zero Copyrighted Assets in Git**: No ROM binaries (`*.nes`, `rom/*.nes`, `rom/*.bin`), CHR dumps, PRG code, or extracted assets may be committed.
  - **Zero Mod-Loaders / Zero Custom Skins**: Strictly authentic ROM-driven visuals and audio only.
  - **Mandatory Runtime ROM Ingestion**: Engine halts gameplay initialization and shows a Missing ROM setup screen unless a valid `Kirby's Adventure` `.nes` file (512 KB PRG-ROM + 256 KB CHR-ROM, Mapper 4 MMC3) is present in `rom/` (or extracted in `user://nes_data/`).
- **Local ROM Metadata (Observed)**:
  - File currently in workspace root (git-ignored): `Kirby's Adventure (USA) (Rev A).nes` (`786,448` bytes).
  - iNES Header: `4E 45 53 1A 20 20 42 00 ...` (Mapper 4 MMC3, `32 x 16 KB` PRG = `524,288` bytes, `32 x 8 KB` CHR = `262,144` bytes, Battery-backed PRG-RAM flag `0x42`).
  - Full SHA-256: `34afcebaf04d57a42c2436fb95b933c7841e1621f1dc3be482380baef33ec3d8` (CRC32 `0x9EFD5757`).
  - PRG SHA-256: `da723759b15e5c468aa7817a8d57b5e41a694ae9f504eab381e3fa8758027156` (CRC32 `0x8FFF3F32`).
  - CHR SHA-256: `7e6189a311a4dee04b63935ac2218586a6e3a57b506e57b3b03e3545f87b2182` (CRC32 `0x7EDAE6F3`).

---

## 2. Hardware Constraints & Environment Quirks
- **Primary Desktop**: Dell OptiPlex 390 (Intel Core i5-2400 Sandy Bridge, 4C/4T, AMD Radeon GPU) running **CachyOS / EndeavourOS Linux** (KDE Plasma).
  - *Hard Constraint*: Sandy Bridge CPU supports **AVX only** (NO AVX2 / FMA3). Pre-compiled binaries with AVX2 will crash with `SIGILL`.
  - *Bun Constraint*: Standard `bun` release crashes on Sandy Bridge; must use **`bun-baseline`**.
  - *C/C++ Flags*: Compile native modules with `-march=sandybridge` or `-mno-avx2`.
  - *Rust Flags*: `.cargo/config.toml` target `rustflags = ["-C", "target-cpu=sandybridge"]`.
- **Mobile Dev Node**: Xiaomi Redmi Note 15 5G (Snapdragon 6 Gen 3, Adreno 710) running Android 16 (HyperOS) with **Termux** + **Fedora PRoot** (`aarch64`, `dnf`).
  - *Hard Constraint*: Optimize for thermal and memory efficiency.
  - *Systemd Absence*: `systemd` is unavailable inside PRoot (`systemctl` fails). Avoid background service commands relying on PID 1 init. Run daemons directly or via script wrappers.
  - *DNF Mirrors*: Keep `max_parallel_downloads=10` and `fastestmirror=True` in `/etc/dnf/dnf.conf`.
- **Primary Shell**: **`fish`** across both Linux desktop and Termux PRoot.
  - Interactive terminal commands must strictly use `fish` syntax (e.g. `set -gx VAR val`, `set -a PATH /path`).
  - Standalone scripts must use POSIX/Bash with explicit shebang (`#!/usr/bin/env bash`).
- **Safe Execution Policy & Repository Git Override**:
  - **Authorized Auto-Commit & Auto-Push (`ReKirby`)**: Per explicit user authorization (2026-11-25), the agent is authorized to run `git add`, `git commit`, and `git push origin main` automatically at the end of each completed milestone/task **without** asking for per-push confirmation, provided:
    1. `git status` confirms zero `.nes`, `.bin`, `.obsidian/`, `.godot/`, or runtime extraction files are staged/tracked.
    2. All verification checks (`godot --headless --path . --quit` and `tests/test_runner.gd` once present) pass 100%.
    3. Changes are batched into clean milestone commits (never micro-commits mid-task).
  - **Other Destructive Ops**: Always request explicit user confirmation before executing destructive file operations (`rm -rf`, overwriting unversioned files), persistent OS/system modifications, or package removals.

---

## 3. Architectural Invariants
- **Deterministic 60 TPS Simulation**: All movement, slopes, inhale/combat hitboxes, enemy AI, and audio frame stepping execute strictly inside `_physics_process(delta)` at 60 Hz.
- **Strict Static Typing**: Every variable, parameter, and return type in GDScript must be explicitly typed.
- **MMC3 Scanline Split**: Playfield renders in `Y: 0..191` with room scroll & room CHR banks; bottom HUD (`Y: 192..239`) remains scroll-locked using HUD CHR banks.
- **HAL LZ77/RLE & 2BPP Ingestion**: All graphics, palettes, metatile maps, and 2A03 APU (Pulse 1/2, Triangle, Noise, DMC) data are extracted at runtime into `user://nes_data/` with zero procedural fallbacks.
- **Vertical Slice Scope**: World 1 (Vegetable Valley) + Whispy Woods boss + Core Kirby mechanics + 4 Copy Abilities (`Sword`, `Fire`, `Spark`, `Beam`).

---

## 4. Active Session Log (ReKirby)
- **[2026-11-25] Workspace Audit, Git Foundation & Clean-Room Policy**:
  - Audited `/sdcard/Documents/Codes/ReKirby`: confirmed workspace currently contains only `Kirby's Adventure (USA) (Rev A).nes` and `docs/`. No Godot project or source files exist yet.
  - Verified ROM iNES header (`4E45531A20204200...`, Mapper 4 MMC3, 512 KB PRG-ROM, 256 KB CHR-ROM) and recorded SHA-256 / CRC32 checksums.
  - Preserved `docs/SOUL.md` and `docs/USER.md` untouched.
  - Created `.gitignore` ignoring `*.nes`, `rom/*.nes`, `rom/*.bin`, `.godot/`, `.obsidian/`, and runtime extraction folders.
  - Rewrote `docs/ARCHITECTURE.md` from scratch for ReKirby (MMC3 banking, scanline HUD split, HAL LZ77/RLE decompression, 2BPP CHR/palette extraction, 16x16 metatiles + slopes, Kirby physics + Sword/Fire/Spark/Beam Copy Abilities, 5-channel 2A03 APU with DMC).
  - Reset `docs/STATUS.md` to the 4-phase Vertical Slice Roadmap (Phase 0–4) with accurate pre-implementation status.
  - Purged all legacy ReTetris session logs and disassembly notes from `docs/MEMORY.md` while keeping Hardware Constraints & Environment Quirks intact.
  - Initialized Git repository on `main`, added `origin` (`git@github.com:Hysm25/ReKirby.git`), created root `AGENTS.md` with coding invariants, verification gate, and user-authorized auto-commit/push policy, persisted `safe.directory` in `~/.gitconfig`, and pushed foundation commits to `origin main`.
  - **Next Step**: Begin Phase 1.5 / Phase 2 (map PRG-ROM metatile/room/palette tables, implement 16x16 metatile physics, slopes, and Kirby's core controller + Copy Abilities).
- **[2026-11-25] Phase 0 & Phase 1 Core Implementation**:
  - Moved `Kirby's Adventure (USA) (Rev A).nes` into `rom/` (verified ignored by `.gitignore`) and added `rom/.gitkeep`.
  - Created `project.godot` (Godot 4.7 `gl_compatibility`, `256x240`, `canvas_items`/`expand`, `default_texture_filter=0`, `60` TPS, strict GDScript warnings enabled, autoloads `EventBus`, `ContentRegistry`, `InputManager`).
  - Implemented `src/core/` (`constants.gd`, `event_bus.gd`, `content_registry.gd`, `input_manager.gd`), `src/importer/` (`rom_validator.gd`, `mmc3_mapper.gd`, `hal_decompressor.gd`, `chr_extractor.gd`, `rom_importer.gd`), and `src/main.gd` + `src/main.tscn` (Mandatory ROM Setup Guard + 256x192 / 256x48 scanline split preview).
  - **Environment Quirk Solved**: Headless `godot` on a fresh `.godot/` folder lacks `.godot/global_script_class_cache.cfg`, causing `class_name` identifiers to fail parsing. Solved by adding explicit `const X = preload("res://...")` references in every script alongside `class_name` and running `SceneTree` tests from `_initialize()`.
  - Added `MAX_ITERATIONS` / directory entry bounds to `while` loops in `hal_decompressor.gd`, `rom_importer.gd`, and `test_importer.gd`.
  - Verified with `timeout 15s godot --headless --path . --quit-after 5` and `timeout 15s godot --headless -s tests/test_runner.gd` (100% pass, including live ROM extraction and `user://nes_data/` reload).
- **[2026-11-25] Repository README & Session Handoff Protocol**:
  - Created root `README.md` documenting clean-room philosophy, `fish` ROM setup into `rom/`, CachyOS/EndeavourOS and Termux Fedora PRoot run/test commands, and Vertical Slice roadmap links.
  - Added mandatory **Session Handoff Protocol** to `AGENTS.md` and `Exact Next Step` tracking to `docs/MEMORY.md`.
  - **File State**: `project.godot`, `.gitignore`, `AGENTS.md`, `README.md`, `rom/.gitkeep`, `src/core/` (`constants.gd`, `event_bus.gd`, `content_registry.gd`, `input_manager.gd`), `src/importer/` (`rom_validator.gd`, `mmc3_mapper.gd`, `hal_decompressor.gd`, `chr_extractor.gd`, `rom_importer.gd`), `src/main.gd`, `src/main.tscn`, `tests/test_runner.gd`, `tests/test_importer.gd`.
  - **Latest Verified Test Result**: `godot --headless --path . --quit-after 5` (exit 0) and `godot --headless -s tests/test_runner.gd` (`tests/test_importer.gd`: `passed=53 failed=0`).
- **[2026-11-25] Phase 1.5 — PRG-ROM World 1 Table & Level Stream Mapping**:
  - Mapped authentic MMC3 Bank 18 (`0x12`), Bank 0 (`0x00`), Bank 5 (`0x05`), Bank 19 (`0x13`), and Bank 56 (`0x38`) structural tables via clean-room PRG-ROM analysis (327 room pointers, 49 tileset pointers, 144 metatile collision properties at `$83D3`, 5-byte door records, slice-indexed entity spawn lists, and BG/Sprite palette tables).
  - Created `src/importer/world_extractor.gd` (`WorldExtractor`) using `MMC3Mapper` + `HALDecompressor` to dynamically extract all 21 World 1 rooms (`R000` Hub, Stages 1-1..1-4 `R043..R060`, Whispy Woods Boss `R030`, Museum `R024`), 9 referenced 16x16 metatile tilesets (256 metatiles each), BG/Sprite palettes, CHR bank bindings, doors, and entity spawns.
  - Updated `src/core/constants.gd` (`EXTRACTION_FORMAT_VERSION = 2`, `WORLD1_DATA_PATH`, `TileCollision` slope/bomb variants + `map_nes_collision_to_enum()`), `src/importer/rom_importer.gd` (caches `world1_data.json` & full `palettes.json` in `user://nes_data/`), `src/core/content_registry.gd` (normalizes `int` room/tileset keys across JSON reload, exposes `has_room`, `get_room_data`, `get_room_ids`, `has_tileset`, `get_tileset_data`, `get_tileset_ids`, `get_metatile`), and `src/main.gd`.
  - **File State**: Added `src/importer/world_extractor.gd` (+ `.uid`); updated `src/core/constants.gd`, `src/core/content_registry.gd`, `src/importer/rom_importer.gd`, `src/main.gd`, `tests/test_importer.gd`, `docs/STATUS.md`, `docs/MEMORY.md`.
  - **Latest Verified Test Result**: `timeout 15s godot --headless --path . --quit-after 5` (exit 0) and `timeout 15s godot --headless -s tests/test_runner.gd` (`tests/test_importer.gd`: `passed=91 failed=0`, exit 0).
- **[2026-11-25] Phase 2 Core — 16x16 Metatile LevelMap, Slope Physics & KirbyController**:
  - Fixed `WorldExtractor.B56_KIRBY_PALETTE_ADDR` from `0xB1D2` (`[0x0F, 0x30, 0x35, 0x25]`) to `0xB1DA` (`[0x0F, 0x35, 0x25, 0x0F]`, authentic Pink Kirby SP0 palette) and updated `tests/test_importer.gd` assertions (`93/93`).
  - Implemented `src/game/level_map.gd` (`LevelMap`): builds 16x16 metatile room textures dynamically from `ContentRegistry` tilesets, 4x1KB BG CHR banks, and room BG palettes; provides deterministic pixel/slope heightmap queries (`SOLID`, `ONE_WAY`, 45°/26.5° slopes, `WATER`, `HAZARD`, `BREAKABLE_STAR`/`BREAKABLE_BOMB`), runtime block breaking, and door detection.
  - Implemented `src/game/kirby_controller.gd` (`KirbyController`): strictly typed 60 TPS movement & physics (`IDLE`, `WALK`, double-tap `RUN` on press/release, `CROUCH`, `SLIDE` breaking star blocks, `ONE_WAY` drop-through, variable `JUMP`/`FALL`, `HOVER` + `AIR_PUFF`, `SWIM` + `WATER_GUN`, `INHALE` cone, `MOUTH_FULL`, `STAR_SPIT`, `SWALLOW`, `HURT`/i-frames + Ability Star drop) composited from ROM CHR bank `128` (`0x80`) + `kirby_default` palette.
  - Updated `src/main.gd` to mount `LevelMap` + `KirbyController` inside `PlayfieldClip256x192` above the `Y=192` HUD split, booting Room `43` (Stage 1-1) with clamped scrolling and `UP` door transitions while preserving the Missing ROM Setup Guard.
  - Added `tests/test_physics.gd` registered in `tests/test_runner.gd` covering slope heightmaps, walk/run/jump, 45°/26.5° slope traversal, one-way drop-through + slide break, hover/air-puff + swim/water-gun, inhale/spit/swallow/damage, and live ROM Stage 1-1 `R043`/`R047` room physics.
  - **File State**: Created `src/game/level_map.gd`, `src/game/kirby_controller.gd`, `tests/test_physics.gd`; updated `src/importer/world_extractor.gd`, `src/main.gd`, `tests/test_importer.gd`, `tests/test_runner.gd`, `docs/STATUS.md`, `docs/MEMORY.md`.
  - **Latest Verified Test Result**: `timeout 15s godot --headless --path . --quit-after 5` (exit 0) and `timeout 15s godot --headless -s tests/test_runner.gd` (`tests/test_importer.gd`: `passed=93 failed=0`, `tests/test_physics.gd`: `passed=53 failed=0`, `TOTAL: passed=146 failed=0`, exit 0).

## 5. Exact Next Step
- **Phase 2.5 — Copy Abilities, Scanline IRQ HUD & Virtual Controls**: Implement `src/game/abilities/` (`Sword`, `Fire`, `Spark`, `Beam`), Scanline IRQ Split HUD (`src/game/hud_renderer.gd` at `Y=192..239` displaying HP pips, lives, score, and Copy Ability portrait card via ROM CHR + HUD palette), `src/game/virtual_gamepad.gd` (desktop keyboard/gamepad + Android touch overlay), wire them into `src/game/kirby_controller.gd` / `src/main.gd`, and expand `tests/test_physics.gd` with Copy Ability hitbox verification.
