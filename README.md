# Stadium Builder

Design-loop prototype. See `CLAUDE.md` for scope and rules.

## Play

    godot --path .          # runs view/main.tscn

3D view. Right-drag (or Q/E) to rotate, WASD/arrows or middle-drag to pan, wheel to zoom.
Pick a stand type and click beside the pitch to build; clicking next to a stand of the
same type extends it. Select a stand to add rows or extend it. Put kiosks and restrooms on
the paved concourse behind stands. Hit Play match: the crowd fills the stands (and bounces
when the atmosphere is good), the fanbase grows, and the takings pay for more stadium.
Toggle Roofs to see the crowd from above.

## Running headless (Godot 4.7)

On a fresh clone, build the class cache once (it lives in the git-ignored `.godot/`):

    godot --headless --import

Tests (GUT, config in `.gutconfig.json`):

    godot --headless -s addons/gut/gut_cmdln.gd

Watch the test count: GUT reports "All tests passed" even when a test script fails to
parse and is skipped (the parse error is printed above the summary).

One matchday per layout, plus a side-by-side table when given 2+ layouts:

    godot --headless -s tools/run_matchday.gd -- data/layouts/terrace_wall.json data/layouts/seated_bowl.json --seed=42 [--big] [--opponent=Name]

Layout comparison (the gate check): N seasons of each layout; season k uses seed S+k for both:

    godot --headless -s tools/compare_layouts.gd -- data/layouts/terrace_wall.json data/layouts/seated_bowl.json [more.json ...] --seed=1 --seasons=200 [--show-season]

With two layouts it adds paired B - A columns; with more it prints one column per layout.

Growth check: a simple bot plays from an empty plot and prints one line per season:

    godot --headless -s tools/autoplay.gd -- --seasons=8 [--seed=S]

ASCII map of a layout (debug):

    godot --headless -s tools/print_geometry.gd -- data/layouts/seated_bowl.json

## Layout

- `sim/` pure simulation (`RefCounted`, no Nodes): `Layout`, `Stand`, `Facility`, `ClubState`, `Fixture`, `QueueModel`, `MatchdaySim`, `MatchdayReport`, `Season`, `SeasonReport`, `SimConfig`
- `data/` all tuning: `tuning.json`, `stand_types.json`, `facility_types.json`, sample `layouts/`
- `tools/` headless runners
- `tests/` GUT tests
