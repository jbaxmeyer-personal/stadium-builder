class_name SimConfig
extends RefCounted
## All tuning data for the sim, loaded from JSON in data/.
## Code reads every number through this object; nothing is hard-coded.

const DEFAULT_DIR := "res://data"

var tuning: Dictionary = {}
var stand_types: Dictionary = {}     # id -> StandType
var facility_types: Dictionary = {}  # id -> FacilityType
var opponents: Array = []           # opponent club names


static func load_default() -> SimConfig:
	return load_from_dir(DEFAULT_DIR)


static func load_from_dir(dir: String) -> SimConfig:
	var cfg := SimConfig.new()
	cfg.tuning = read_json(dir.path_join("tuning.json"))
	var stands: Dictionary = read_json(dir.path_join("stand_types.json"))
	for id in stands:
		cfg.stand_types[id] = StandType.from_dict(id, stands[id])
	var facilities: Dictionary = read_json(dir.path_join("facility_types.json"))
	for id in facilities:
		cfg.facility_types[id] = FacilityType.from_dict(id, facilities[id])
	if FileAccess.file_exists(dir.path_join("opponents.json")):
		cfg.opponents = read_json(dir.path_join("opponents.json"))["names"]
	return cfg


static func read_json(path: String) -> Variant:
	var text := FileAccess.get_file_as_string(path)
	assert(text != "", "SimConfig: cannot read %s" % path)
	var data: Variant = JSON.parse_string(text)
	assert(data != null, "SimConfig: invalid JSON in %s" % path)
	return data


## Look up a tuning value by slash path, e.g. "demand/base".
func value(path: String) -> Variant:
	var node: Variant = tuning
	for key in path.split("/"):
		assert(node is Dictionary and node.has(key), "SimConfig: missing tuning key '%s'" % path)
		node = node[key]
	return node


func num(path: String) -> float:
	return float(value(path))


func integer(path: String) -> int:
	return int(value(path))


func stand_type(id: String) -> StandType:
	assert(stand_types.has(id), "Unknown stand type '%s'" % id)
	return stand_types[id]


func facility_type(id: String) -> FacilityType:
	assert(facility_types.has(id), "Unknown facility type '%s'" % id)
	return facility_types[id]


## Stand type ids in a stable order (as listed in the JSON).
func stand_type_ids() -> Array:
	return stand_types.keys()
