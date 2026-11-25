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
  - **Next Step**: Relocate `Kirby's Adventure (USA) (Rev A).nes` into `rom/` and begin Phase 0/1 (`project.godot` + ROM Extractor & Asset Importer).
