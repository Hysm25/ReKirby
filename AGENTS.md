# ReKirby Execution Blueprint (`AGENTS.md`)

> **Project**: **ReKirby** — Clean-Room PC & Android Port of *Kirby's Adventure* (NES / Famicom, 1993 — Mapper 4 MMC3) in **Godot 4 (Strictly Typed GDScript)**.

---

## 1. Context Hierarchy
Before beginning any task, read these workspace context files in order:
1. `AGENTS.md` (this operational blueprint)
2. `docs/SOUL.md` (agent persona, output rules, and hardware/shell conventions)
3. `docs/USER.md` (user profile, Sandy Bridge AVX-only desktop & Snapdragon ARM64 Termux/PRoot constraints)
4. `docs/ARCHITECTURE.md` (MMC3, HAL LZ77/RLE, 2BPP CHR, 16x16 metatiles, Copy Abilities, and 2A03 APU specs)
5. `docs/STATUS.md` (Vertical Slice Roadmap and current milestone checklist)
6. `docs/MEMORY.md` (persistent architectural invariants, environment quirks, and session log)

**Immutability Rule**: Never modify `docs/SOUL.md` or `docs/USER.md` unless explicitly instructed by the user.

---

## 1.5 Session Handoff Protocol & Continuous ROM-Fidelity Parity Loop (Mandatory)
1. **Start of Every New Session**:
   - Read `AGENTS.md`, `docs/STATUS.md`, and `docs/MEMORY.md` first (along with the full context hierarchy) so work resumes seamlessly from the recorded state without asking the user to re-explain past progress.
2. **End of Every Turn / Milestone (Before Committing & Pushing)**:
   - Inspect runtime/ROM implementation state honestly and update the **Estimated ROM Fidelity %** scorecard and checklist in `docs/STATUS.md`, marking completed parity items done.
   - **Continuous Parity Rule**: **NEVER** set `Exact Next Step` to passive user instructions such as `"run godot --path ."` or `"wait for user testing"`. Always set `Exact Next Step` in `docs/MEMORY.md` to the **next highest-priority engineering / ROM-extraction task** from `docs/STATUS.md`'s Fidelity Backlog Queue so every subsequent session prompt automatically drives the port closer to 100% 1:1 ROM parity.
   - Record exact modified/created file paths and verified test counts/commands in `docs/MEMORY.md`.

---

## 2. Coding & Clean-Room Invariants
1. **Strictly Typed GDScript**:
   - Every variable, constant, parameter, and return type must declare explicit static types (`var hp: int = 6`, `func step(delta: float) -> void:`). Untyped GDScript is prohibited.
2. **Deterministic 60 TPS Simulation**:
   - All physics, slope queries, inhale/combat hitboxes, enemy AI, MMC3 scanline split state, and APU frame stepping run strictly inside `_physics_process(delta)` locked at 60 TPS.
3. **Zero Copyrighted Assets in Git**:
   - Never stage, commit, or push `.nes`, `.bin`, `.rom`, `.fds`, `.sav`, raw CHR/PRG dumps, or runtime extracted directories (`rom/`, `nes_data/`, `extracted/`, `user/`).
   - Never track `.obsidian/` or `.godot/`.
4. **Mandatory Runtime ROM Ingestion (Zero Procedural Fallbacks)**:
   - Visuals, palettes, level layouts, and 2A03 APU audio/DPCM data must be extracted at runtime from a user-supplied `.nes` ROM in `rom/` into `user://nes_data/`.
   - Procedural tile/audio fallback approximations are strictly prohibited. If no valid ROM is found, boot must halt at the Missing ROM setup screen.
5. **Zero Mod-Loaders / Custom Skins**:
   - Do not introduce skin loaders, custom palette overrides, or modding frameworks.
6. **Hardware & Shell Portability**:
   - Target `gl_compatibility` and low memory/CPU overhead for both **Intel Core i5-2400 (Sandy Bridge, AVX-only, no AVX2)** and **Snapdragon 6 Gen 3 / Adreno 710 (Android / Fedora PRoot aarch64)**.
   - Interactive shell commands must use `fish` syntax; standalone scripts must use `#!/usr/bin/env bash`.

---

## 3. Verification Gate
Before committing any code or project changes:
1. Run Godot headless boot verification:
   ```fish
   godot --headless --path . --quit
   ```
2. Run the automated headless test suite (once `tests/test_runner.gd` exists):
   ```fish
   godot --headless -s tests/test_runner.gd
   ```
3. Confirm **100% of checks and tests pass** with zero errors or leaks, and update `docs/STATUS.md` and `docs/MEMORY.md` to reflect verified progress.

---

## 4. Autonomous Git Commit & Push Policy (User Authorized)
- **Explicit Authorization**: The user has explicitly authorized automatic `git add`, `git commit`, and `git push origin main` at the end of every completed milestone or task **without asking for per-push confirmation**, overriding the generic push-confirmation guardrail for this repository.
- **Pre-Commit & Pre-Push Checklist (Mandatory)**:
  1. Verify via `git status --short` and `git ls-files` that zero `.nes` ROMs, `.bin` dumps, `.obsidian/` files, `.godot/`, or `nes_data/`/`extracted/`/`user/` files are untracked-exposed, staged, or committed.
  2. Confirm all verification gate checks (`godot --headless --path . --quit` and `godot --headless -s tests/test_runner.gd`, when present) pass 100%.
  3. Batch related work into clean, meaningful milestone commits — **never** push trivial micro-edits mid-task.
  4. Keep the destructive-action guardrail intact for non-push operations (`rm -rf`, overwriting unversioned files, OS package removals).
