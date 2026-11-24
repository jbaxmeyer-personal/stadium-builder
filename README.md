# Stadium Builder

Design-loop prototype. See `CLAUDE.md` for scope and rules.

## Running headless (Godot 4.7)

On a fresh clone, build the class cache once (it lives in the git-ignored `.godot/`):

    godot --headless --import

Tests (GUT, config in `.gutconfig.json`):

    godot --headless -s addons/gut/gut_cmdln.gd

One matchday per layout, plus a side-by-side table when given 2+ layouts:

    godot --headless -s tools/run_matchday.gd -- data/layouts/terrace_wall.json data/layouts/seated_bowl.json --seed=42 [--big] [--opponent=Name]

ASCII map of a layout (debug):

    godot --headless -s tools/print_geometry.gd -- data/layouts/seated_bowl.json

## Layout

- `sim/` pure simulation (`RefCounted`, no Nodes): `Layout`, `Stand`, `Facility`, `ClubState`, `Fixture`, `QueueModel`, `MatchdaySim`, `MatchdayReport`, `SimConfig`
- `data/` all tuning: `tuning.json`, `stand_types.json`, `facility_types.json`, sample `layouts/`
- `tools/` headless runners
- `tests/` GUT tests
