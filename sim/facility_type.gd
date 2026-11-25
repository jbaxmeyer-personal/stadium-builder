class_name FacilityType
extends RefCounted
## Anything placeable that isn't a stand. `layer` says where it goes:
##   concourse   - on concourse tiles behind stands (food, bars, shops, restrooms, first aid, fan zones)
##   bowl        - mounted on a stand (video boards, ribbon boards, scoreboards, sound systems)
##   outside     - open ground around the stadium (car parks, bus stops)
##   underground - below the plot (parking garages, subway stations)
## `kind` says what it does in the sim (see MatchdaySim).

const LAYERS := ["concourse", "bowl", "outside", "underground"]

var id: String
var display_name: String
var kind: String
var layer: String
var size: Vector2i = Vector2i.ONE
var styles: Array = ["standard"]
var build_cost: float
var upkeep_per_match: float
var service_rate_per_min: float = 0.0   # halftime kinds
var spend_per_customer: float = 0.0
var capacity: float = 0.0               # transport: fans per match
var sponsor_per_match: float = 0.0      # boards
var atmosphere_bonus: float = 0.0
var mood_bonus: float = 0.0             # first aid, fan zones
var coverage: float = 0.0               # fans one of these looks after
var power: float = 0.0                  # utility units per match
var water: float = 0.0
var income_per_match: float = 0.0       # museums, hotels
var box_price: float = 0.0              # executive boxes: per box per match when sold
var requires_tiers: int = 1             # bowl items that need an upper tier


static func from_dict(type_id: String, d: Dictionary) -> FacilityType:
	var t := FacilityType.new()
	t.id = type_id
	t.display_name = d["name"]
	t.kind = d["kind"]
	t.layer = d.get("layer", "concourse")
	var sz: Array = d.get("size", [1, 1])
	t.size = Vector2i(int(sz[0]), int(sz[1]))
	t.styles = d.get("styles", ["standard"])
	t.build_cost = float(d["build_cost"])
	t.upkeep_per_match = float(d["upkeep_per_match"])
	t.service_rate_per_min = float(d.get("service_rate_per_min", 0))
	t.spend_per_customer = float(d.get("spend_per_customer", 0))
	t.capacity = float(d.get("capacity", 0))
	t.sponsor_per_match = float(d.get("sponsor_per_match", 0))
	t.atmosphere_bonus = float(d.get("atmosphere_bonus", 0))
	t.mood_bonus = float(d.get("mood_bonus", 0))
	t.coverage = float(d.get("coverage", 0))
	t.power = float(d.get("power", 0))
	t.water = float(d.get("water", 0))
	t.income_per_match = float(d.get("income_per_match", 0))
	t.box_price = float(d.get("box_price", 0))
	t.requires_tiers = int(d.get("requires_tiers", 1))
	return t
