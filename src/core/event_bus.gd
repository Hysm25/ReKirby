extends Node
## Global typed signal bus for ReKirby runtime state, extraction, HUD, and audio events.

# ROM ingestion lifecycle
signal rom_extraction_started(rom_path: String)
signal rom_extraction_completed(manifest: Dictionary)
signal rom_extraction_failed(reason: String)
signal rom_missing()

# Core game state and stage flow
signal game_state_changed(new_state: int, previous_state: int)
signal room_changed(world_id: int, stage_id: int, room_id: int)

# Player / HUD status
signal hp_changed(current_hp: int, max_hp: int)
signal lives_changed(lives: int)
signal score_changed(score: int, delta_points: int)
signal copy_ability_changed(ability: int)
signal boss_hp_changed(boss_id: int, current_hp: int, max_hp: int)

# Audio triggers
signal sfx_requested(sfx_id: int)
signal bgm_requested(track_id: int)
signal audio_stop_requested()
