# Stadium Builder

A SimCity-style stadium builder. You start a small club on an empty plot, build a soccer
stadium piece by piece, host matches, and watch the ground, the crowds and the club grow
over many seasons, climbing the divisions.

## What the game is (use this to settle scope arguments)

1. **Fun to build and watch grow.** Like SimCity: relaxed, creative, not a hard optimisation
   puzzle. A sensible player always grows; bad choices only slow you down.
2. **The stadium is the game.** The team is context only: no tactics, transfers or match
   simulation beyond the result. Matchdays are a reward moment, not a minigame.
3. **Everything comes in versions.** Every buildable thing has several looks (roofs,
   corners, facades, kiosks, floodlights, surroundings...). Variety is where the fun is.
4. **The crowd is the reward.** Fans, flags, tifos, flares and noise make a good stadium feel alive.
5. **It should look good.** Target: at least SimCity 4 level of visual detail and polish.
   Natural, textured and well lit, not bright and plasticky. Keep improving it.
6. **Soccer only.**

## How it plays (current state)

- Three views, like SimCity's layers: **Stadium** (stands, bowl gear, outside), **Concourse**
  (stands go see-through; food, bars, shops, restrooms, first aid, fan zones; one level per
  stand tier) and **Underground** (garages, subway).
- Stands: five types (terrace, seated, premium, family, safe standing), on the four sides or
  in corners (square or rounded), up to 12 rows deep and 3 tiers; upper tiers set back over
  extra ground; deep and multi-tier stands have their concourse inside.
- Buy land to grow the plot. Transport (car parks, bus stops, garage, subway, train station)
  caps how many fans can get there. Power and water are a per-match bill, no pipes.
- A real league: 20 teams, home and away (38 matchdays), a table; top 3 promoted from the
  Fourth Division, top 2 from the Third and Second (no relegation). A well-run club takes
  roughly 10-15 seasons to reach the top. Team strength comes from the squad budget (wages, an expense every match)
  plus luck; home crowds help. Away games earn TV money only. Evening games, rain and
  snow, four divisions, milestones that pay out and unlock big-ticket items.
- Club identity: name, colours, stadium name, naming-rights sponsor.
- Save/load with autosave after every action.

ROADMAP.md lists what's done and what's next. README.md has the controls.

## Architecture rules

- **Godot 4.7, GDScript.** Forward+ renderer.
- **The simulation is pure logic** (`RefCounted` classes in `sim/`, no Nodes), runs headless and
  is fully deterministic: same layout + seed + commands = same game. The view only reads sim
  state and calls `Season` commands. Cosmetic choices (roofs, facades, colours, surroundings,
  floodlights, pitch pattern) are stored in the layout/club but the sim ignores them.
- **Data-driven:** stand types, facilities, tuning, milestones, divisions, sponsors and
  opponents live in `data/*.json`. No magic numbers in sim code.
- **Layouts and saves are JSON.** Old saves must keep loading (use `.get(key, default)`).
- **Tests:** GUT unit tests for `sim/` (determinism, queue maths, placement rules, economy,
  progression, save/load). Run them after every sim change; keep them passing.

```
sim/        pure simulation (Layout, Stand, Facility, Season, MatchdaySim, ...)
data/       all tuning and content, sample layouts in data/layouts/
view/       3D renderer (stadium_renderer.gd), crowd display, audio, camera, main.gd (glue)
view/ui/    the HUD (game_ui.gd) and code-drawn icons (icons.gd)
assets/     CC0 assets: polyhaven/ (textures, HDRI sky), kenney/ (models, sprites, icons)
tools/      headless runners: run_matchday, compare_layouts, autoplay (growth bot), print_geometry
tests/      GUT tests
```

## Assets

- Only CC0 assets (Poly Haven, Kenney). Credit every source in CREDITS.md and keep each
  kit's licence file. Download at modest resolution (1k textures) to keep the repo small.
- Stands, roofs, seats, fans, floodlights and boards are generated in code because no asset
  fits our grid, tiers and corners. Generic props (cars, trains, trees, buildings) come from kits.

## Working rules

- Show, don't tell: after any visual change, render screenshots (headless with Xvfb and the
  lavapipe Vulkan driver, see below), look at them, fix what's wrong, and send the good ones.
- Prefer small, visible increments, committed and pushed to `main` as they land.
- When a design question comes up that this file doesn't answer, make a sensible call for
  small things and ask for big ones.
- Keep the UI SimCity-like: icons, drag and drop, short tips, little text in your face.

## Running

    godot --headless --import                              # once on a fresh clone
    godot --headless -s addons/gut/gut_cmdln.gd            # tests (check the test count)
    godot --headless -s tools/autoplay.gd -- --seasons=8   # does a sensible player grow?
    godot --path .                                         # play

Screenshots in this container:

    VK_ICD_FILENAMES=/opt/lavapipe/lvp_icd.json xvfb-run -a -s "-screen 0 1280x720x24" \
        godot --rendering-driver vulkan -s <script that builds a scene and saves PNGs>

GDScript here treats inferred-Variant warnings as errors: give explicit types when
inferring from dictionaries, arrays or untyped calls.
