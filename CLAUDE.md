# Stadium Builder

A stadium builder/tycoon game. You design and run a soccer stadium on a fixed plot and budget. Each matchday tests the layout, the revenue funds expansion and the club, and the club climbs the league tiers.

Full design doc: https://claude.ai/artifact/C66wKhwu3KSUcktF6RX4Gy

## Pillars (use these to settle scope arguments)

1. **The stadium is the game.** The team is context only: no tactics, no transfers, no watching matches.
2. **Every matchday is a test.** Layout choices must produce visibly different outcomes.
3. **Atmosphere is engineered.** Stand design → noise → home advantage → wins.
4. **The crowd is the reward.** (Rendering comes later, not in this milestone.)
5. **Soccer only.** No other sports until after launch.

## Current milestone: design-loop prototype (2–3 weeks)

**The question it answers:** do design choices visibly matter? Two different layouts on the same budget must play out noticeably differently, in a way the player wants to experiment with.

**Gate:** the player replays to try a *different* layout, not just a bigger one.

### In scope

- Top-down 2D or simple 3D view with **grey boxes only**
- Fixed grid plot (start at 60×40 tiles) with a pitch fixed in the center
- **Stands** placed along the four pitch sides; the player sets length and type:
  - **Terrace:** cheap to build, cheap tickets, standing room, high noise
  - **Seated:** mid cost, mid price, mid noise
  - **Premium:** expensive to build, high ticket price, low noise
- **Concourse** tiles behind stands, with placeable **food kiosks** and **restroom blocks** (each with a build cost and a service rate)
- **Budget:** starting cash; building costs money; per-match maintenance cost per seat and facility
- **Matchday sim** (statistical, see the model below) producing a **matchday report**:
  - attendance by stand, revenue by source (tickets, food, premium)
  - atmosphere score
  - halftime queues per facility (wait time, lost sales)
  - fan mood change
  - result (W/D/L)
- **Mini-season:** 10 home matches. Between matches the player can build, demolish and change ticket prices
- Results feed form, and form feeds demand, so crowds grow with success
- End-of-season summary screen
- **Headless layout comparison runner:** load two saved layouts plus a seed and run N seasons each, then print a comparison table. This is how we check the gate objectively.

### Out of scope (do NOT build yet)

Parametric stand meshes, crowd rendering, tifos and flares, agents and flow fields, league tables, promotion and relegation, the revenue-split slider, transit, utilities, fan segments beyond what stand type implies, art, audio, menus beyond the minimum.

## Simulation model (starting point; all numbers live in config and get tuned)

- **Demand** per match = base demand × form multiplier × opponent multiplier (some matches are marked "big") × price elasticity per stand type
- **Attendance** per stand = min(capacity, demand share for that stand's price tier)
- **Atmosphere** = Σ(stand noise factor × fill rate × proximity factor), normalized to 0–100. Empty seats kill atmosphere
- **Home advantage** = f(atmosphere), which shifts the win/draw/loss probabilities from a fixed base squad strength
- **Halftime rush:** a share of fans want food and a share want a restroom inside a 15-minute window
  - Each fan goes to the nearest facility by walking distance from their stand
  - Queue wait = queued fans ÷ service rate. Fans who can't be served in the window = lost sale + mood penalty
- **Fan mood** carries between matches and feeds demand
- **Revenue** = tickets + food sales + premium. **Costs** = maintenance
- Everything uses a **seeded RNG**: same layout + same seed = same result

## Architecture rules

- **Godot 4.x (latest stable), GDScript.**
- **Simulation is pure logic with no Node dependencies.** Use `RefCounted` classes in `sim/` that run headless. The view only reads sim state and sends player commands.
- **Data-driven:** stand types, facility types and tuning constants live in `data/` as `.tres` Resources or JSON. No magic numbers in code.
- **Layouts serialize to JSON** (save/load plus the comparison runner).
- Suggested structure:
  ```
  sim/        # pure simulation: layout, demand, matchday, economy, season
  data/       # stand types, facility types, tuning constants
  view/       # scenes, grid rendering, build tools, report UI
  tools/      # headless layout comparison runner
  tests/      # GUT unit tests for sim/
  ```
- **Tests:** unit-test the sim with GUT, especially determinism (same seed → same output) and the queue math.

## Working rules

- Keep the prototype ugly and fast. Grey boxes, debug labels, a minimal UI.
- When a design question comes up that this file doesn't answer, ask. Don't invent features.
- Prefer small, playable increments: get a single matchday working end-to-end before the season loop.
- Report sim numbers in the matchday report so balance problems are visible.
