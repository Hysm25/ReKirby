class_name MMC3Mapper
extends RefCounted
## Virtual Nintendo MMC3 (TxROM / iNES Mapper 4) PRG/CHR bank mapper and scanline IRQ state.

const Constants = preload("res://src/core/constants.gd")

var _prg_rom: PackedByteArray = PackedByteArray()
var _chr_rom: PackedByteArray = PackedByteArray()
var _prg_bank_count_8k: int = 0
var _chr_bank_count_1k: int = 0

var _bank_select: int = 0
var _registers: PackedInt32Array = PackedInt32Array([0, 2, 4, 5, 6, 7, 0, 1])
var _mirroring_horizontal: bool = false
var _prg_ram_enabled: bool = true
var _prg_ram_write_protect: bool = false

var _irq_latch: int = 0
var _irq_counter: int = 0
var _irq_reload_pending: bool = false
var _irq_enabled: bool = false
var _irq_pending: bool = false


func _init(prg_data: PackedByteArray = PackedByteArray(), chr_data: PackedByteArray = PackedByteArray()) -> void:
	load_rom_data(prg_data, chr_data)


func load_rom_data(prg_data: PackedByteArray, chr_data: PackedByteArray) -> void:
	_prg_rom = prg_data
	_chr_rom = chr_data
	_prg_bank_count_8k = maxi(1, _prg_rom.size() / Constants.PRG_BANK_8K_SIZE)
	_chr_bank_count_1k = maxi(1, _chr_rom.size() / Constants.CHR_BANK_1K_SIZE)
	reset()


func reset() -> void:
	_bank_select = 0
	_registers = PackedInt32Array([0, 2, 4, 5, 6, 7, 0, 1])
	_mirroring_horizontal = false
	_prg_ram_enabled = true
	_prg_ram_write_protect = false
	_irq_latch = 0
	_irq_counter = 0
	_irq_reload_pending = false
	_irq_enabled = false
	_irq_pending = false


func write_register(cpu_addr: int, value: int) -> void:
	var masked_addr: int = cpu_addr & 0xE001
	var byte_val: int = value & 0xFF
	match masked_addr:
		0x8000:
			_bank_select = byte_val
		0x8001:
			var reg_idx: int = _bank_select & 0x07
			_registers[reg_idx] = byte_val
		0xA000:
			_mirroring_horizontal = (byte_val & 0x01) != 0
		0xA001:
			_prg_ram_enabled = (byte_val & 0x80) != 0
			_prg_ram_write_protect = (byte_val & 0x40) != 0
		0xC000:
			_irq_latch = byte_val
		0xC001:
			_irq_counter = 0
			_irq_reload_pending = true
		0xE000:
			_irq_enabled = false
			_irq_pending = false
		0xE001:
			_irq_enabled = true


func is_prg_mode_swapped() -> bool:
	return (_bank_select & 0x40) != 0


func is_chr_a12_inverted() -> bool:
	return (_bank_select & 0x80) != 0


func is_mirroring_horizontal() -> bool:
	return _mirroring_horizontal


func is_irq_pending() -> bool:
	return _irq_pending


func clear_irq_pending() -> void:
	_irq_pending = false


func clock_scanline() -> bool:
	if _irq_counter == 0 or _irq_reload_pending:
		_irq_counter = _irq_latch
		_irq_reload_pending = false
	else:
		_irq_counter -= 1

	if _irq_counter == 0 and _irq_enabled:
		_irq_pending = true
	return _irq_pending


func resolve_prg_8k_bank(cpu_addr: int) -> int:
	var slot: int = (cpu_addr >> 13) & 0x03
	var raw_bank: int = 0
	var second_last: int = maxi(0, _prg_bank_count_8k - 2)
	var last_bank: int = maxi(0, _prg_bank_count_8k - 1)
	var prg_mode_1: bool = is_prg_mode_swapped()

	match slot:
		0: # $8000-$9FFF
			raw_bank = second_last if prg_mode_1 else (_registers[6] & 0x3F)
		1: # $A000-$BFFF
			raw_bank = _registers[7] & 0x3F
		2: # $C000-$DFFF
			raw_bank = (_registers[6] & 0x3F) if prg_mode_1 else second_last
		3: # $E000-$FFFF
			raw_bank = last_bank
	return raw_bank % _prg_bank_count_8k


func resolve_prg_offset(cpu_addr: int) -> int:
	if cpu_addr < 0x8000 or cpu_addr > 0xFFFF:
		return -1
	var bank_8k: int = resolve_prg_8k_bank(cpu_addr)
	return bank_8k * Constants.PRG_BANK_8K_SIZE + (cpu_addr & 0x1FFF)


func read_prg_byte(cpu_addr: int) -> int:
	var offset: int = resolve_prg_offset(cpu_addr)
	if offset < 0 or offset >= _prg_rom.size():
		return 0
	return _prg_rom[offset]


func read_prg_slice(cpu_addr: int, length: int) -> PackedByteArray:
	var out: PackedByteArray = PackedByteArray()
	if length <= 0:
		return out
	out.resize(length)
	for i: int in range(length):
		var cur_addr: int = cpu_addr + i
		if cur_addr > 0xFFFF:
			out.resize(i)
			break
		out[i] = read_prg_byte(cur_addr)
	return out


func resolve_chr_1k_bank(ppu_addr: int) -> int:
	var slot: int = (ppu_addr >> 10) & 0x07
	var raw_bank: int = 0
	if not is_chr_a12_inverted():
		match slot:
			0:
				raw_bank = _registers[0] & 0xFE
			1:
				raw_bank = (_registers[0] & 0xFE) | 1
			2:
				raw_bank = _registers[1] & 0xFE
			3:
				raw_bank = (_registers[1] & 0xFE) | 1
			4:
				raw_bank = _registers[2]
			5:
				raw_bank = _registers[3]
			6:
				raw_bank = _registers[4]
			7:
				raw_bank = _registers[5]
	else:
		match slot:
			0:
				raw_bank = _registers[2]
			1:
				raw_bank = _registers[3]
			2:
				raw_bank = _registers[4]
			3:
				raw_bank = _registers[5]
			4:
				raw_bank = _registers[0] & 0xFE
			5:
				raw_bank = (_registers[0] & 0xFE) | 1
			6:
				raw_bank = _registers[1] & 0xFE
			7:
				raw_bank = (_registers[1] & 0xFE) | 1
	return raw_bank % _chr_bank_count_1k


func resolve_chr_offset(ppu_addr: int) -> int:
	if ppu_addr < 0x0000 or ppu_addr > 0x1FFF:
		return -1
	var bank_1k: int = resolve_chr_1k_bank(ppu_addr)
	return bank_1k * Constants.CHR_BANK_1K_SIZE + (ppu_addr & 0x03FF)
