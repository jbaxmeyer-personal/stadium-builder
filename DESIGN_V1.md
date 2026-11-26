# Stadium Builder v1: from proof of concept to a shippable game

The proof of concept proved the loop. v1 makes it **yours**: you start small and plain,
and every piece you place begins bare and grows as you add to it. A thousand players
should end up with a thousand different grounds.

## Principles (the snowman rule)

1. **Placed things start bare.** A new stand is an open concrete terrace or bank of grey
   seats: no roof, no name, no gear, no extras. You add each layer yourself.
2. **Every layer is a choice with many versions.** Each choice has many options, and
   colours are never limited to presets: there is always a full colour picker.
3. **The player builds the site too:** roads, car-park access, paths, paving, trees,
   lighting. SimCity-style: things need connecting.
4. **Small to big, like real football.** Lower-league grounds look like lower-league
   grounds: one or two stands, a clubhouse, grass banks, a rail round the pitch. Corners,
   tiers and wraparound roofs come with money and time.
5. **The whole world, not just England.** Styles and props from every football culture.
6. **Realistic money.** Spending choices have real consequences at the extremes.

## Research notes (what real grounds are made of)

- **English non-league / lower leagues:** a rail round the pitch (hard standing), grass
  banks, one covered terrace ("the Shed") with roof pillars, a small seated main stand, a
  clubhouse with bar and changing rooms (FA grading requires one higher up), a turnstile
  hut, floodlight poles (4-6 slim masts), dugouts, a tea bar. Stands rarely cover the
  full length; ends are often open. [FA ground grading; Warrington Town; AFC Fylde]
- **Germany:** huge safe-standing ends (Dortmund's Südtribüne holds about 25,000), rail
  seats that convert for European games, steep single tiers, roofs that trap the noise,
  translucent or membrane roofs, open corners (Mainz), solar roofs (Freiburg).
- **South America:** steep stands pressed against the pitch (La Bombonera), sunken
  pitches, a huge bowl with one modern side stand, high fences and moats, giant flags
  hung down the stands, paper streamers, drums and trumpets, concrete everywhere,
  painted stands in club colours.
- **Italy:** a running track round the pitch, curved ends ("curve") where the ultras
  stand, choreographies (coreografie), smoke, two-tier concrete bowls; new grounds are
  dropping the track.
- **Japan / Korea:** roofs over every seat, two-deck rectangular stadiums,
  community-hub facilities, clean modern materials; older multi-purpose stadiums have
  tracks and open sides.
- **Spain / Portugal:** steep vertical tiers, sun and shade pricing, white concrete,
  dramatic cantilevers, scoreboards in the corners.
- **Netherlands / Scandinavia:** artificial pitches, compact boxes, retractable roofs.
- **Turkey / Greece / Balkans:** pyro, steep tight bowls, fences, huge home ends.
- **USA (MLS):** a supporters' section with a tifo wall, a canopy roof on one side only,
  brick-and-steel looks, a river or downtown backdrop.

## Plan (each step is built, screenshotted, checked, committed)

### Step 1: Start and identity
- [x] New-game screen: club name, short name, founded year, kit colours (full colour
      picker), badge designer (shape, split pattern, two or three colours, initials or
      symbol, stars), or upload your own PNG logo; stadium name; surroundings; sky
- [x] Club settings move to a small side button (editable later, not front and centre)
- [x] The pitch starts placed in the middle; "Move pitch" shows in red which stands it
      would remove and asks to confirm

### Step 2: Bare by default, layers to add
- [x] New stands: open (no roof), grey concrete, name off, no extras, no gear
- [x] New pitch: plain grass, no boards, no dugouts, no corner flags, no nets: each one
      is added and styled separately
- [x] Corner flags: pole colour, flag colour, pattern (plain, halves, quarters, stripes,
      club badge)
- [x] Full colour picker (hue wheel, saturation, value, hex) next to every preset swatch

### Step 3: Build the site (SimCity-style)
- [x] Roads: drag road tiles; car parks, bus stops and the train station only count if
      a road connects them to the ring road
- [x] Paths and paving: drag paving; fans walk on paths from transport to turnstiles; a
      little crowd and atmosphere penalty when the walk is long or over grass
- [x] Landscaping: trees (species), hedges, flower beds, benches, bins, flagpoles, lamps,
      fences; all draggable
- [x] Tutorial steps for roads, paths and car parks

### Step 4: Lower-league kit (start small)
- [x] Pitch-side rail and hard standing, grass banks, a clubhouse, a turnstile hut, a tea
      bar, slim floodlight masts (4 or 6), a "Shed" covered terrace with pillars
- [x] Partial-length stands look right (open ends); a stand can be short and offset

### Step 5: World styles (versions everywhere)
- [ ] Stand styles: English classic, German steep wall with rail seats, South American
      concrete bowl (painted in club colours), Italian curva (behind a running track),
      Japanese fully roofed two-deck, Spanish vertical tiers, MLS canopy and supporters' end
- [ ] Pitch surrounds: track, moat and fence, rail, artificial, sunken pitch
- [ ] Crowd cultures: giant flags down the stand, paper streamers, drums, choreographies,
      pyro, scarves, smoke, umbrellas, fan banners on fences
- [ ] Roofs: membrane, translucent, solar, steel truss, cantilever, barrel, sawtooth
- [ ] Floodlights: slim masts, lattice pylons, roof strip, ring, corner "candles" (Italy)

### Step 6: Realistic balance
Results (tools/autoplay.gd --strategy=...): cheap finishes bottom with 3-6 wins a season and
hoards cash; all-in climbs fast then hits debt, administration and relegation (boom and bust);
balanced is promoted around season 5, reaches the Premier around season 10 and becomes a
top side by seasons 13-15. Costs now include club overheads per division, stewards per fan,
and interest on debt.
- [x] Minimum squad spend: the club stays low (a ceiling about two divisions up, at best)
- [x] All income on the squad: promotions come but the ground can't keep up (capacity,
      transport and facility caps limit income and crowds), so the club struggles
- [x] A balanced player climbs in 10-15 seasons; the bot tests all three strategies

### Step 7: Graphics (the gap list in GAPS.md continues)
- [ ] Every material textured (stand concrete, seats, roofs, steel, glass), with grime in
      corners, AO and normal detail; less "Lego"
- [ ] More props everywhere: signage, bins, barriers, railings, CCTV, PA horns, stewards

### Step 8: Shippable polish
- [ ] Main menu, settings (graphics quality, audio), save slots, smooth performance,
      no dead ends, every button does something sensible, tooltips everywhere
