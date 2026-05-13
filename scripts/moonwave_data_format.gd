extends Node

class_name MWDat

const MAGIC := "MWDAT"
const VERSION := 1

static func save(path: String, data: Dictionary) -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	
	# Header
	file.store_buffer(MAGIC.to_utf8_buffer())
	file.store_16(VERSION)
	
	# Data
	_write_dict(file, data)
	return OK

static func load(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	
	# Validate header
	var magic := file.get_buffer(5).get_string_from_utf8()
	if magic != MAGIC:
		push_error("MWDat: Invalid file format")
		return {}
	
	var version := file.get_16()
	if version != VERSION:
		push_warning("MWDat: Version mismatch (got %d, expected %d)" % [version, VERSION])
	
	return _read_dict(file)

static func _write_value(file: FileAccess, value) -> void:
	match typeof(value):
		TYPE_BOOL:
			file.store_8(0x01)
			file.store_8(int(value))
		TYPE_INT:
			file.store_8(0x02)
			file.store_64(value)
		TYPE_FLOAT:
			file.store_8(0x03)
			file.store_double(value)
		TYPE_STRING:
			file.store_8(0x04)
			var buf = value.to_utf8_buffer()
			file.store_32(buf.size())
			file.store_buffer(buf)
		TYPE_DICTIONARY:
			file.store_8(0x05)
			_write_dict(file, value)
		TYPE_ARRAY:
			file.store_8(0x06)
			_write_array(file, value)
		TYPE_VECTOR2:
			file.store_8(0x07)
			file.store_float(value.x)
			file.store_float(value.y)
		TYPE_VECTOR3:
			file.store_8(0x08)
			file.store_float(value.x)
			file.store_float(value.y)
			file.store_float(value.z)
		_:
			push_warning("MWDat: Unsupported type %d, skipping" % typeof(value))

static func _write_dict(file: FileAccess, dict: Dictionary) -> void:
	file.store_32(dict.size())
	for key in dict:
		var key_buf := str(key).to_utf8_buffer()
		file.store_32(key_buf.size())
		file.store_buffer(key_buf)
		_write_value(file, dict[key])

static func _write_array(file: FileAccess, arr: Array) -> void:
	file.store_32(arr.size())
	for item in arr:
		_write_value(file, item)

static func _read_value(file: FileAccess):
	var type := file.get_8()
	match type:
		0x01: return bool(file.get_8())
		0x02: return file.get_64()
		0x03: return file.get_double()
		0x04:
			var len := file.get_32()
			return file.get_buffer(len).get_string_from_utf8()
		0x05: return _read_dict(file)
		0x06: return _read_array(file)
		0x07: return Vector2(file.get_float(), file.get_float())
		0x08: return Vector3(file.get_float(), file.get_float(), file.get_float())
		_:
			push_error("MWDat: Unknown type tag 0x%02X" % type)
			return null

static func _read_dict(file: FileAccess) -> Dictionary:
	var dict := {}
	var count := file.get_32()
	for i in count:
		var key_len := file.get_32()
		var key := file.get_buffer(key_len).get_string_from_utf8()
		dict[key] = _read_value(file)
	return dict

static func _read_array(file: FileAccess) -> Array:
	var arr := []
	var count := file.get_32()
	for i in count:
		arr.append(_read_value(file))
	return arr
