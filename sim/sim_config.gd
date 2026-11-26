class_name SimConfig
extends RefCounted
## All tuning data for the sim, loaded from JSON in data/.
## Code reads every number through this object; nothing is hard-coded.

const DEFAULT_DIR := "res://data"

var tuning: Dictionary = {}
var stand_types: Dictionary = {}     # id -> StandType
var facility_types: Dictionary = {}  # id -> FacilityType
var opponents: Array = []           # opponent club names
var milestones: Array = []          # [{fans, name, reward, unlocks}], ascending
var divisions: Array = []          # league ladder, bottom first
var cup: Dictionary = {}            # the national cup: rounds, schedule, prizes
var continental: Array = []         # continental competitions by top-division finish
var continental_schedule: Dictionary = {}
var sponsors: Dictionary = {}       # id -> {name, suffix, fee_base, fee_per_1000_places, mood_penalty}
var site_items: Dictionary = {}     # id -> {name, group (road/path/green), cost, tip}


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
	if FileAccess.file_exists(dir.path_join("milestones.json")):
		cfg.milestones = read_json(dir.path_join("milestones.json"))["milestones"]
	if FileAccess.file_exists(dir.path_join("league.json")):
		var lg: Dictionary = read_json(dir.path_join("league.json"))
		cfg.divisions = lg["divisions"]
		cfg.cup = lg.get("cup", {})
		cfg.continental = lg.get("continental", [])
		cfg.continental_schedule = lg.get("continental_schedule", {})
	if FileAccess.file_exists(dir.path_join("sponsors.json")):
		for sp in read_json(dir.path_join("sponsors.json"))["sponsors"]:
			cfg.sponsors[sp["id"]] = sp
	if FileAccess.file_exists(dir.path_join("site_items.json")):
		cfg.site_items = read_json(dir.path_join("site_items.json"))["items"]
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
## Division settings (clamped to the ladder; neutral if there's no league data).
func division(i: int) -> Dictionary:
	if divisions.is_empty():
		return { "name": "League", "demand_multiplier": 1.0, "tv_per_match": 0, "squad_wage": 6000 }
	return divisions[clampi(i, 0, divisions.size() - 1)]


## Fans needed to unlock something (0 = available from the start).
func unlock_fans(id: String) -> float:
	for m in milestones:
		if id in m["unlocks"]:
			return float(m["fans"])
	return 0.0


func stand_type_ids() -> Array:
	return stand_types.keys()
