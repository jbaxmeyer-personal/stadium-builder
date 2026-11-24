class_name QueueModel
extends RefCounted
## Halftime queue at one facility. All arrivals hit the facility in one rush.
## Their walk there and back comes out of the halftime window.
##   usable window = window - mean round-trip walk (>= 0)
##   served        = min(arrivals, floor(rate * usable window))
##   lost          = arrivals - served
##   max wait      = arrivals / rate   (queued fans / service rate)
##   avg wait      = served / (2 * rate)  (mean wait of served fans in a rush)


static func simulate(arrivals: int, rate_per_min: float, window_min: float, round_trip_min := 0.0) -> Dictionary:
	var usable: float = max(0.0, window_min - round_trip_min)
	var capacity := 0 if rate_per_min <= 0.0 else floori(rate_per_min * usable)
	var served: int = min(arrivals, capacity)
	return {
		"arrivals": arrivals,
		"served": served,
		"lost": arrivals - served,
		"usable_window_min": usable,
		"wait_max_min": INF if rate_per_min <= 0.0 else arrivals / rate_per_min,
		"wait_avg_min": 0.0 if rate_per_min <= 0.0 else served / (2.0 * rate_per_min),
	}
