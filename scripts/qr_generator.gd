class_name QRGenerator
extends RefCounted

# Pure GDScript ISO/IEC 18004 QR Code Generator (Byte mode, Level L, Versions 1..5)
# Supports up to 106 UTF-8 bytes with zero external dependencies.

const VERSION_SPECS := {
	1: {"size": 21, "data_cw": 19, "ec_cw": 7, "align": []},
	2: {"size": 25, "data_cw": 34, "ec_cw": 10, "align": [6, 18]},
	3: {"size": 29, "data_cw": 55, "ec_cw": 15, "align": [6, 22]},
	4: {"size": 33, "data_cw": 80, "ec_cw": 20, "align": [6, 26]},
	5: {"size": 37, "data_cw": 108, "ec_cw": 26, "align": [6, 30]},
}

# Format info bits for EC Level L (01) + Mask (0..7), BCH(15,5) + XOR 0x5412
const FORMAT_INFO_L := [
	0x77c4, 0x72f3, 0x7daa, 0x789d,
	0x662f, 0x6318, 0x6c41, 0x6976
]

static var _gf_exp: PackedInt32Array
static var _gf_log: PackedInt32Array
static var _gf_ready := false

static func _init_gf() -> void:
	if _gf_ready:
		return
	_gf_exp.resize(512)
	_gf_log.resize(256)
	var x := 1
	for i in range(255):
		_gf_exp[i] = x
		_gf_log[x] = i
		x <<= 1
		if (x & 0x100) != 0:
			x ^= 0x11d
	for i in range(255, 512):
		_gf_exp[i] = _gf_exp[i - 255]
	_gf_ready = true

static func _gf_mul(a: int, b: int) -> int:
	if a == 0 or b == 0:
		return 0
	return _gf_exp[_gf_log[a] + _gf_log[b]]

static func _rs_generator(degree: int) -> PackedInt32Array:
	_init_gf()
	var poly := PackedInt32Array([1])
	for i in range(degree):
		var next := PackedInt32Array()
		next.resize(poly.size() + 1)
		next.fill(0)
		var root := _gf_exp[i]
		for j in range(poly.size()):
			next[j] ^= poly[j]
			next[j + 1] ^= _gf_mul(poly[j], root)
		poly = next
	return poly

static func _rs_encode(data: PackedByteArray, ec_len: int) -> PackedByteArray:
	var gen := _rs_generator(ec_len)
	var buf := PackedInt32Array()
	buf.resize(data.size() + ec_len)
	buf.fill(0)
	for i in range(data.size()):
		buf[i] = data[i]
	for i in range(data.size()):
		var coef := buf[i]
		if coef != 0:
			for j in range(gen.size()):
				buf[i + j] ^= _gf_mul(gen[j], coef)
	var out := PackedByteArray()
	out.resize(ec_len)
	for i in range(ec_len):
		out[i] = buf[data.size() + i]
	return out

static func encode_matrix(text: String) -> Dictionary:
	var bytes := text.to_utf8_buffer()
	var version := -1
	for v in range(1, 6):
		var spec: Dictionary = VERSION_SPECS[v]
		if bytes.size() <= int(spec["data_cw"]) - 2:
			version = v
			break
	if version == -1:
		return {"size": 0, "modules": PackedByteArray()}

	var spec: Dictionary = VERSION_SPECS[version]
	var size: int = spec["size"]
	var data_cw: int = spec["data_cw"]
	var ec_cw: int = spec["ec_cw"]

	# Build bit stream (Byte mode = 0100, 8-bit char count for V1..V9)
	var bits := PackedByteArray()
	_append_bits(bits, 0b0100, 4)
	_append_bits(bits, bytes.size(), 8)
	for b in bytes:
		_append_bits(bits, b, 8)

	var max_bits := data_cw * 8
	var terminator_len := mini(4, max_bits - bits.size())
	_append_bits(bits, 0, terminator_len)
	while bits.size() % 8 != 0:
		bits.append(0)

	var data_bytes := PackedByteArray()
	for i in range(0, bits.size(), 8):
		var val := 0
		for j in range(8):
			val = (val << 1) | bits[i + j]
		data_bytes.append(val)

	var pad_toggle := false
	while data_bytes.size() < data_cw:
		data_bytes.append(0x11 if pad_toggle else 0xEC)
		pad_toggle = not pad_toggle

	var ec_bytes := _rs_encode(data_bytes, ec_cw)
	var full_bits := PackedByteArray()
	for b in data_bytes:
		_append_bits(full_bits, b, 8)
	for b in ec_bytes:
		_append_bits(full_bits, b, 8)

	# Build base matrix & reserved mask
	var base := PackedByteArray()
	base.resize(size * size)
	base.fill(0)
	var reserved := PackedByteArray()
	reserved.resize(size * size)
	reserved.fill(0)

	_place_finder(base, reserved, size, 0, 0)
	_place_finder(base, reserved, size, size - 7, 0)
	_place_finder(base, reserved, size, 0, size - 7)
	_place_timing(base, reserved, size)

	var align: Array = spec["align"]
	for ax in align:
		for ay in align:
			if (ax == 6 and ay == 6) or (ax == 6 and ay == size - 7) or (ax == size - 7 and ay == 6):
				continue
			_place_alignment(base, reserved, size, ax, ay)

	# Dark module
	base[(4 * version + 9) * size + 8] = 1
	reserved[(4 * version + 9) * size + 8] = 1

	# Reserve format info areas
	_reserve_format(reserved, size)

	# Place data bits in zigzag
	var bit_idx := 0
	var dir_up := true
	var col := size - 1
	while col > 0:
		if col == 6:
			col -= 1
		var row := (size - 1) if dir_up else 0
		while row >= 0 and row < size:
			for c_off in range(2):
				var cx := col - c_off
				var idx := row * size + cx
				if reserved[idx] == 0:
					var bit_val := 0
					if bit_idx < full_bits.size():
						bit_val = full_bits[bit_idx]
						bit_idx += 1
					base[idx] = bit_val
			row += -1 if dir_up else 1
		dir_up = not dir_up
		col -= 2

	# Try all 8 masks and pick lowest penalty
	var best_mask := 0
	var best_score := 999999999
	var best_matrix := PackedByteArray()
	for mask_id in range(8):
		var candidate := base.duplicate()
		for r in range(size):
			for c in range(size):
				var idx := r * size + c
				if reserved[idx] == 0 and _mask_bit(mask_id, r, c):
					candidate[idx] ^= 1
		_place_format(candidate, size, mask_id)
		var score := _penalty_score(candidate, size)
		if score < best_score:
			best_score = score
			best_mask = mask_id
			best_matrix = candidate

	return {"size": size, "modules": best_matrix, "mask": best_mask, "version": version}

static func create_texture(text: String, scale: int = 8, quiet_zone: int = 4) -> ImageTexture:
	var res := encode_matrix(text)
	var size: int = res.get("size", 0)
	if size <= 0:
		return null
	var modules: PackedByteArray = res["modules"]
	var total := (size + quiet_zone * 2) * scale
	var img := Image.create(total, total, false, Image.FORMAT_RGB8)
	img.fill(Color.WHITE)
	for r in range(size):
		for c in range(size):
			if modules[r * size + c] == 1:
				var px := (c + quiet_zone) * scale
				var py := (r + quiet_zone) * scale
				img.fill_rect(Rect2i(px, py, scale, scale), Color(0.06, 0.09, 0.16))
	return ImageTexture.create_from_image(img)

static func _append_bits(arr: PackedByteArray, val: int, count: int) -> void:
	for i in range(count - 1, -1, -1):
		arr.append((val >> i) & 1)

static func _place_finder(mat: PackedByteArray, res: PackedByteArray, size: int, x0: int, y0: int) -> void:
	for dy in range(-1, 8):
		for dx in range(-1, 8):
			var x := x0 + dx
			var y := y0 + dy
			if x < 0 or x >= size or y < 0 or y >= size:
				continue
			var dark := 0
			if dx >= 0 and dx <= 6 and dy >= 0 and dy <= 6:
				if dx == 0 or dx == 6 or dy == 0 or dy == 6 or (dx >= 2 and dx <= 4 and dy >= 2 and dy <= 4):
					dark = 1
			mat[y * size + x] = dark
			res[y * size + x] = 1

static func _place_timing(mat: PackedByteArray, res: PackedByteArray, size: int) -> void:
	for i in range(8, size - 8):
		var dark := 1 if (i % 2 == 0) else 0
		mat[6 * size + i] = dark
		res[6 * size + i] = 1
		mat[i * size + 6] = dark
		res[i * size + 6] = 1

static func _place_alignment(mat: PackedByteArray, res: PackedByteArray, size: int, cx: int, cy: int) -> void:
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			var dark := 1 if (maxi(absi(dx), absi(dy)) != 1) else 0
			var idx := (cy + dy) * size + (cx + dx)
			mat[idx] = dark
			res[idx] = 1

static func _reserve_format(res: PackedByteArray, size: int) -> void:
	for i in range(9):
		if i != 6:
			res[8 * size + i] = 1
			res[i * size + 8] = 1
	for i in range(8):
		res[8 * size + (size - 1 - i)] = 1
		if i < 7:
			res[(size - 1 - i) * size + 8] = 1

static func _place_format(mat: PackedByteArray, size: int, mask_id: int) -> void:
	var bits: int = FORMAT_INFO_L[mask_id]
	# Top-left horizontal & vertical
	for i in range(6):
		mat[8 * size + i] = (bits >> (14 - i)) & 1
	mat[8 * size + 7] = (bits >> 8) & 1
	mat[8 * size + 8] = (bits >> 7) & 1
	mat[7 * size + 8] = (bits >> 6) & 1
	for i in range(6):
		mat[(5 - i) * size + 8] = (bits >> i) & 1
	# Top-right horizontal & bottom-left vertical
	for i in range(8):
		mat[8 * size + (size - 1 - i)] = (bits >> i) & 1
	for i in range(7):
		mat[(size - 1 - i) * size + 8] = (bits >> (14 - i)) & 1

static func _mask_bit(mask_id: int, r: int, c: int) -> bool:
	match mask_id:
		0: return (r + c) % 2 == 0
		1: return r % 2 == 0
		2: return c % 3 == 0
		3: return (r + c) % 3 == 0
		4: return (int(r / 2) + int(c / 3)) % 2 == 0
		5: return ((r * c) % 2 + (r * c) % 3) == 0
		6: return (((r * c) % 2 + (r * c) % 3) % 2) == 0
		7: return (((r + c) % 2 + (r * c) % 3) % 2) == 0
	return false

static func _penalty_score(mat: PackedByteArray, size: int) -> int:
	var score := 0
	# Rule 1: 5+ consecutive same color in row/col
	for r in range(size):
		var run_len := 1
		for c in range(1, size):
			if mat[r * size + c] == mat[r * size + c - 1]:
				run_len += 1
				if run_len == 5:
					score += 3
				elif run_len > 5:
					score += 1
			else:
				run_len = 1
	for c in range(size):
		var run_len := 1
		for r in range(1, size):
			if mat[r * size + c] == mat[(r - 1) * size + c]:
				run_len += 1
				if run_len == 5:
					score += 3
				elif run_len > 5:
					score += 1
			else:
				run_len = 1
	# Rule 2: 2x2 blocks
	for r in range(size - 1):
		for c in range(size - 1):
			var v := mat[r * size + c]
			if v == mat[r * size + c + 1] and v == mat[(r + 1) * size + c] and v == mat[(r + 1) * size + c + 1]:
				score += 3
	# Rule 4: dark ratio
	var dark_count := 0
	for v in mat:
		dark_count += v
	var percent := int((dark_count * 100) / (size * size))
	var k := int(absi(percent - 50) / 5)
	score += k * 10
	return score
