class_name StandType
extends RefCounted

var id: String
var display_name: String
var capacity_per_tile: int
var build_cost_per_place: float
var reference_price: float
var noise: float
var elasticity: float
var upkeep_per_place: float
var demand_share: float
var hospitality_per_head: float
var demand_pool: String     # stand types that share another type's fans (a grass bank shares the terrace's)


static func from_dict(type_id: String, d: Dictionary) -> StandType:
	var t := StandType.new()
	t.id = type_id
	t.display_name = d["name"]
	t.capacity_per_tile = int(d["capacity_per_tile"])
	t.build_cost_per_place = float(d["build_cost_per_place"])
	t.reference_price = float(d["reference_price"])
	t.noise = float(d["noise"])
	t.elasticity = float(d["elasticity"])
	t.upkeep_per_place = float(d["upkeep_per_place"])
	t.demand_share = float(d["demand_share"])
	t.hospitality_per_head = float(d["hospitality_per_head"])
	t.demand_pool = String(d.get("demand_pool", type_id))
	return t
