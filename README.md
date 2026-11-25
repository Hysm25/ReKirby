# ReKirby

> **Clean-Room PC & Android Port of *Kirby's Adventure* (NES / Famicom, 1993 — Mapper 4 MMC3)**  
> Built with **Godot 4 (Strictly Typed GDScript)** at a deterministic **60 TPS** simulation rate.

---

## Philosophy & Clean-Room Invariants

- **Zero Copyrighted Assets in Git**: No Nintendo or HAL Laboratory ROMs (`*.nes`), CHR pattern dumps, PRG binaries, or extracted assets are stored in this repository.
- **Mandatory Runtime ROM Extraction**: On startup, ReKirby scans `rom/` for a user-supplied NTSC *Kirby's Adventure* `.nes` image (512 KB PRG-ROM + 256 KB CHR-ROM, Mapper 4 MMC3), validates its iNES header and CRC32/SHA-256 checksums, and extracts authentic graphics and data into `user://nes_data/`.
- **Zero Procedural Fallbacks & Zero Mod-Loaders**: If no valid ROM is present, gameplay refuses to start and halts at the `256x240` Missing ROM setup screen. No custom skin loaders or procedural tile/audio approximations are included.
- **Strictly Typed & Hardware-Portable**: 100% static typing in GDScript targeting `gl_compatibility` and nearest-neighbor pixel rendering for low-overhead execution on both legacy x86_64 desktops (**Intel Core i5-2400 AVX-only**) and mobile **ARM64** (**Snapdragon 6 Gen 3 / Adreno 710**).

---

## Setup (`fish` Shell)

Place your own legally obtained `Kirby's Adventure (USA) (Rev A).nes` ROM inside the git-ignored `rom/` directory:

```fish
mkdir -p rom
cp "/path/to/Kirby's Adventure (USA) (Rev A).nes" rom/
```

Verify the `.nes` file remains excluded from version control:

```fish
git status --short
```

---

## Running & Headless Verification

### Linux Desktop (CachyOS / EndeavourOS) & Android (Termux + Fedora PRoot `aarch64`)

1. **Headless Boot Check**:
   ```fish
   godot --headless --path . --quit-after 5
   ```
2. **Automated Headless Test Suite**:
   ```fish
   godot --headless -s tests/test_runner.gd
   ```
3. **Interactive Launch** (Desktop / X11 / Wayland):
   ```fish
   godot --path .
   ```

---

## Vertical Slice Roadmap

| Phase | Milestone | Status |
| :--- | :--- | :--- |
| **Phase 0** | Project Skeleton, Core Autoloads & Missing ROM Boot Guard | Completed |
| **Phase 1** | ROM Validator, MMC3 Mapper, HAL LZ77/RLE Decompressor & 2BPP CHR/Table Extractor | Completed |
| **Phase 2** | 16x16 Metatile Slope Physics, Kirby Controller & Copy Abilities (`Sword`, `Fire`, `Spark`, `Beam`) | Completed |
| **Phase 3** | 2A03 APU 5-Channel Audio Engine (`Pulse 1/2`, `Triangle`, `Noise`, `DMC`) & PRG-ROM Player | Completed |
| **Phase 4** | Title Screen, World 1 (Vegetable Valley) & Whispy Woods Boss Vertical Slice | Core Completed (`320/320` Headless Tests Pass; On-Device Verification Pending) |

For full technical specifications and live task tracking, see:
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
- [docs/STATUS.md](docs/STATUS.md)
- [docs/MEMORY.md](docs/MEMORY.md)
