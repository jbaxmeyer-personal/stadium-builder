class_name FacilityType
extends RefCounted

var id: String
var display_name: String
var kind: String  # "food" or "restroom"; matches halftime/share keys
var build_cost: float
var service_rate_per_min: float
var upkeep_per_match: float
var spend_per_customer: float


static func from_dict(type_id: String, d: Dictionary) -> FacilityType:
	var t := FacilityType.new()
	t.id = type_id
	t.display_name = d["name"]
	t.kind = d["kind"]
	t.build_cost = float(d["build_cost"])
	t.service_rate_per_min = float(d["service_rate_per_min"])
	t.upkeep_per_match = float(d["upkeep_per_match"])
	t.spend_per_customer = float(d["spend_per_customer"])
	return t
