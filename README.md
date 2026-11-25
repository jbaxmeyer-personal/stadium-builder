# Stadium Builder

Design-loop prototype. See `CLAUDE.md` for scope and rules.

## Play

    godot --path .          # runs view/main.tscn

3D view. Right-drag (or Q/E) to rotate, WASD/arrows or middle-drag to pan, wheel to zoom.

- **Build tab:** pick a stand type (Terrace, Seated, Premium, Family, Safe Standing) and
  click beside the pitch, or in a corner gap for a corner stand. Clicking next to a stand
  of the same type extends it. Select a stand to add rows, extend it, pick its roof
  (Modern / Classic / None) or change its seat colour. Kiosks and restrooms go on the
  paved concourse behind stands.
- **Layers** (buttons top-left): **Stadium** for stands, bowl gear (video boards, ribbon
  boards, scoreboards, sound systems; click a stand) and outside transport (car parks, bus
  stops); **Concourse** turns the stands see-through so you can place food stands, bars,
  club shops, restrooms, first aid and fan zones; **Underground** for parking garages and a
  subway station. Transport decides how many fans can get to the ground.
- **Tiers:** select a stand and press Add tier to stack up to three tiers. Each tier gets
  its own concourse level; in the Concourse view use the Ground / Level 1 / Level 2 buttons.
- **Camera:** on-screen buttons (zoom, rotate, tilt, reset) or mouse wheel, right-drag,
  WASD/arrows and Q/E, in every view.
- **Club tab:** club name (shown on your main stand), home and trim colours (or a kit
  preset), ticket prices.
- **Play match:** the crowd fills the stands in your colours and bounces when the
  atmosphere is good; the fanbase grows and the takings pay for more stadium.

See ROADMAP.md for what's next.

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
