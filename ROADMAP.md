# Stadium Builder roadmap

The goal: a fun, SimCity-style game where you build a cool stadium over time and
watch it (and your club) grow. Decisions matter, but a sensible player always grows.

## Done

- Sim: fanbase that grows every match, demand by stand type, atmosphere, results,
  halftime queues, money, fan mood; seasons that chain forever; seeded and tested (GUT)
- 3D builder: click beside the pitch to build, click next to a stand to extend it,
  add rows, demolish; kiosks and restrooms on the concourse; orbit camera
- Stand types: Terrace, Seated, Premium, Family, Safe Standing
- Corner stands that fill the gaps between sides, square or rounded
- Roof styles per stand: Modern (tilted back so rain runs off away from the pitch),
  Classic (pitched with gable and pillars), Barrel (curved), Goalpost truss, None
- Save / load, with autosave after every action
- Three layers like SimCity: **Stadium** (stands, bowl gear, outside), **Concourse**
  (stands go see-through; food stands, bars, club shops, restrooms, first aid, fan zones)
  and **Underground** (parking garages, subway station)
- In the bowl: video boards (classic or LED wall), ribbon boards, scoreboards (digital or
  retro), sound systems: atmosphere and sponsor money
- Transport caps the crowd (car parks, bus stops, garages, subway); power and water are
  a per-match utility bill (no pipe-laying)
- Multi-tier stands (up to 3 tiers); each tier has its own concourse level, and the
  Concourse view has a level picker (Ground / Level 1 / Level 2)
- Camera controls in every view: on-screen zoom / rotate / tilt / reset buttons plus
  mouse wheel, right-drag, WASD and Q/E; the camera follows the level you're on
- Big stands (5+ rows) have their concourse inside, under the raised back rows, like
  real grounds; small stands keep it behind. The ground behind a big stand is free
- Matchday moment: named opponents, scorelines, evening kick-offs under floodlights
  (night lighting), a score banner with a noise meter and a camera sweep round the ground
- Big stands take ground: upper tiers set back over extra rows, single tiers up to 12
  rows deep (Kop / Wall style); multi-tier stands have their concourse under the upper tier
- Buy land: grow the plot in strips on any side (prices rise with each strip) for bigger
  stands, car parks, garages, stations and fan zones
- Floodlight styles: corner pylons (kept clear of the stands), roof-mounted, side masts
- Growth milestones (5k, 8k, 12k, 20k, 30k, 45k, 70k fans): cash rewards, a celebration
  in the matchday banner, and unlocks. Basics are always open; big-ticket items (video
  boards, sound, upper tiers, executive boxes, garage, subway, train station, museum,
  hotel, naming rights) unlock as the club grows; locked buttons show the fans needed
- Executive boxes between tiers (glass or classic), sold to corporate fans
- Around the ground: statues (3 styles), ticket office, club museum, hotel, train station
- Stadium name, plus naming-rights sponsors (more money, fans grumble a little)
- League climb: four divisions (data/league.json). Hit the points target to go up; higher
  divisions bring bigger crowds and TV money but tougher opponents. No relegation
- Procedural crowd sound (no audio files): murmur while building, roar scaled by
  atmosphere, goal cheers, clap chants from loud crowds; Sound toggle
- Stand facades (concrete, brick, glass, steel, club colour) and pitch patterns
  (stripes, wide stripes, checkerboard, plain)
- Weather: rain and snow (winter matches) keep fans away from uncovered stands;
  rain/snow particles, overcast sky, snow-dusted pitch on matchday
- Crowd display: waving flags (more in loud stands), slogan banners on stand fronts in
  club colours, tifo card displays on the home end for big loud matches, flares and
  coloured smoke on terraces when the atmosphere is high
- Graphics: Poly Haven textures and sky; Kenney cars, trains, streetlights and trees;
  detailed fans (hair, skin, scarves, arms up when it's loud) in the stands and walking
  outside; individual seats; stair gangways; facade pilasters, windows and entrances;
  roof rafters; LED boards and dugouts; selectable surroundings (town, suburbs, city,
  fields, forest) with real-scale buildings; tall city buildings fade near the camera
- Facilities come in styles (food booth / food truck / pie hut, pub / modern bar, ...)
- Club identity: name (shown on the main stand), home/trim colours with kit presets,
  per-stand seat colours; the crowd wears your colours
- Crowd fills the seats after each match and bounces with the atmosphere
- Tools: matchday runner, layout comparison, autoplay growth bot
- Landscape and light: terrain with hills, a mountain range, carved rivers, lakes and
  streams; roads and pavements that follow the ground; four skies (sunny, cloudy,
  overcast, golden hour) with matching sun and shadows; haze only toward the horizon
- Per-stand extras, each switchable: name sign (text, roof or wall, size, colour,
  lit at night), roof flags, LED strip, clock, fan banners; cladding includes fins,
  metal panels and a colonnade; a cable-stayed mast roof
- Pitch: five grass types, seven mowing patterns (incl. diagonal, diamonds, circles)
  that shift shade with the viewing angle; goals in three styles with net colour
  and mesh pattern
- History books: season records, year-by-year profit and loss by line, match list, charts
- v1 Step 1, identity: a new-game screen (names, founding year, three colours with full
  colour pickers, badge designer or uploaded logo, surroundings, sky); the badge shows in
  the top bar, on roof crests and on corner flags and flagpoles; the pitch starts placed
  and can be moved (stands move with it; ones that won't fit show red, with a confirm)
- v1 Step 2, bare by default: new stands are open with no name or extras; a roof is a
  paid layer; the pitch starts with no boards, dugouts, nets or corner flags; corner
  flags in six patterns with any colours
- v1 Step 3, the site: access roads (transport needs a road to the street), four kinds
  of paving (fans walk faster than on grass; a long walk costs crowds), and landscaping
  (four trees, hedges, flower beds, benches, bins, lamps, flagpoles, railings)

## Principle: everything comes in versions

Every buildable thing should have several looks/variants to pick from (roofs, corners,
facades, kiosks, shops, decorations...). Variety is where the fun is.

## Next up (in order)

See DESIGN_V1.md: Step 4 (lower-league kit), Step 5 (world styles), Step 6 (realistic
balance at the extremes), Step 7 (graphics), Step 8 (shippable polish).

## Later / ideas

- More styles for everything (stand facades, concourse floors, roof cladding)
- Utility upgrades: solar roof, rainwater recycling to cut the bill

- Pitch styles (stripe patterns), running track option
- Seat-colour patterns (club name or crest spelled out in seats)
- Weather and seasons (snow, rain)
- Steam workshop-style sharing of stadium layouts
