# Stadium Builder

**Play it (Windows):** [download the latest build](https://github.com/jbaxmeyer-personal/stadium-builder/releases/latest/download/StadiumBuilder-Windows.zip),
unzip it and double-click `StadiumBuilder.exe`. All builds: [Releases](https://github.com/jbaxmeyer-personal/stadium-builder/releases/latest).

Design-loop prototype. See `CLAUDE.md` for scope and rules.

## Play

    godot --path .          # runs view/main.tscn

- **New game:** set up your club first: name, short name, founding year, three club
  colours (presets or the full colour wheel), a badge (shape, pattern, symbol, letters,
  stars) or your own uploaded PNG/JPG logo, the ground's name, surroundings and sky.
  Change any of it later with the shirt button on the left rail.
- **Build bar** (bottom): pick a category (Stands, In the bowl, Transport, Roads & paths,
  Landscaping, Around, Land, Looks), then drag a tile onto the ground, or click it and click
  the ground. Select and Bulldoze sit at the end. Locked items show the fans needed.
- **Everything starts bare:** a new stand is open to the sky with no name or extras; the
  pitch has no boards, dugouts, corner flags or nets. Add each layer yourself (a roof costs
  money but keeps fans coming in rain and snow).
- **Roads & paths, landscaping:** drag to draw a line (hold Shift for an area); bulldoze
  drags clear them. Car parks, bus stops and stations only bring fans if they sit on the
  street at the plot edge or an access road joins them to it ("⚠ NO ROAD" shows if not).
  Fans walk faster on paving than grass; a long walk puts some off ("LONG WALK").
- **Views** (left rail): Stadium, Concourse (stands go see-through; level buttons appear
  for multi-tier stands) and Underground; zoom, rotate and reset the camera.
- **Click a stand** for its card: add rows or tiers, extend, roof, walls, seat colour,
  corner shape, its name sign (on/off, text, roof or wall, size, colour, lit at night),
  roof crest (on/off, position, size, lit), seat pattern (rows, blocks, checks, mosaic,
  a word, a crest), extras (flags, LED strip, clock, banners), mounted gear with its own
  options (video board size/frame/content, scoreboard digits, speaker type and colour),
  demolish. Corner stands get the same extras.
- **Looks** also sets the pitchside: ad boards, dugouts, corner flags (pattern, pole and
  flag colours) and the surround (grass, artificial, running track, gravel).
- **Top bar**: club, cash, fans, capacity, mood, division and promotion progress; the chart
  opens the history books (seasons, a year-by-year profit and loss, this season's matches,
  charts); the cog opens settings (roofs, sound, save, load, new game). The shirt on the
  left rail opens the club window (identity, badge, ticket prices, sponsor).
- **Play match** (bottom right) plays the next matchday: your game (home or away) and the
  rest of the league. Seasons are a 20-team league, home and away (38 matchdays); the top 3
  go up and the bottom 3 go down (none up from the Premier, none down from the Fourth). The result card shows your score, scorers, shots, possession, league position
  and the money in and out; the trophy button opens the table, all results, your fixtures
  and the **squad budget** (players' wages per match: spend more for a stronger team).
- **Mouse:** wheel zooms toward the cursor; left-drag on the ground moves the map;
  right-drag rotates and tilts; middle-drag also moves. A click (no drag) uses the tool.
- **Start:** a new game is a plot in the middle of town with the pitch in the middle. Move
  it with Stands > Pitch: stands move with it, and any that would no longer fit show in
  red and you're asked to confirm.
- **Building a stand:** pick a type, then press on the strip beside the pitch and drag:
  along the touchline sets its length, away from the pitch sets its rows. Release to build.
  A plain click builds a short stand.
- **Right-click or Esc** puts the tool down (again: clears the selection).
- **Keys:** WASD/arrows move, Q/E rotate, R/F zoom.

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
