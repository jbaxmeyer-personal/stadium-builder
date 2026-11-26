# Gaps to Cities: Skylines quality

Worked through top to bottom, one at a time. `[x]` = done (with the commit), `[ ]` = to do.
Every item is checked by rendering screenshots and comparing against the references.

## A. Scale and correctness bugs
- [x] A1 Car park shows ~6 cars for ~600 fans: size it to its capacity (rows of bays, lanes, many cars, kerbs, lighting, trees in islands)
- [x] A2 Bus stop / train station / garage / subway capacities match what you see (buses queued, platform length)
- [x] A3 Facility footprints read at the right real-world scale next to stands (kiosks, toilets vs a 20 m stand)
- [x] A4 Museum/hotel/ticket office placement fails silently in some spots: show why, snap to valid ground

## B. Stadium architecture
- [x] B1 Stand back walls: real cladding (panels with depth, mullions, louvres), stair/ramp towers, glazed concourse bands, dark base
- [x] B2 Stand side/end walls: finished faces, vomitories, exposed raking beams when open
- [ ] B3 Roof undersides: steel purlins, lights, speakers, translucent leading edge
- [x] B4 Roof materials: standing-seam metal with sheen and panel lines, gutters, edge flashing
- [ ] B5 Seats: real moulded seat shape, row numbers, aisle steps with yellow nosing, handrails
- [ ] B6 Concrete materials: board-marked, weathered tone variation, AO in corners (not plastic white)
- [x] B7 Corner stands: same facade treatment as side stands
- [ ] B8 Floodlight pylons and roof-mounted lights: detailed heads, ladders, cable trays
- [ ] B9 Pitch-side: perimeter wall, tunnel entrance, technical area, ball boys' stools, camera gantry
- [ ] B10 Executive boxes and hospitality glass with interiors lit at night

## C. Pitch
- [ ] C1 Pitch grass: real turf texture, mowing sheen from the sun angle, wear in goalmouths
- [ ] C2 Line paint with slight blur/soak, corner flags, penalty spots
- [ ] C3 Goal nets with depth and shadow; goal frames with proper profile

## D. Terrain and nature
- [ ] D1 Terrain textures: higher-res grass, meadow flowers, dirt paths, field edges
- [x] D2 Grass clutter (3D tufts) near the camera
- [ ] D3 Tree variety and LOD: more species, sizes, autumn tints; clumps not grids; impostors far away
- [ ] D4 Bushes, hedgerows and flower beds with proper leaf cards
- [ ] D5 Water: reflections, shoreline foam, depth colour, reeds
- [ ] D6 Rocks and cliffs on slopes

## E. Town and roads
- [x] E1 Roads: lane markings, kerbs, pavements, crossings, junction shapes, road texture with wear
- [x] E2 Streetlights along roads, signs, traffic lights at junctions
- [ ] E3 Building variety: more house types, porches, dormers, gardens with fences and sheds
- [ ] E4 Building materials: textured brick/render/siding, window frames with depth, roof textures
- [ ] E5 Town blocks: back gardens, alleys, parking courts, corner shops
- [ ] E6 City edge: mid-rises with detailed facades, rooftop details
- [ ] E7 Industrial/commercial zones with lots, trucks, signage
- [ ] E8 Railway line with track, catenary, a station

## F. Life
- [x] F1 Moving cars on roads
- [ ] F2 Pedestrians walking to the ground on matchday, crowds at turnstiles
- [x] F3 Parked cars in streets and driveways
- [ ] F4 Buses arriving at the bus stop on matchday
- [ ] F5 Birds / flags in wind / smoke from chimneys

## G. Lighting and rendering
- [ ] G1 Sun and sky: richer HDRI usage, sun colour by time of day, soft long shadows
- [ ] G2 Ambient occlusion tuned for small details; contact shadows
- [x] G3 Colour grading: gentle contrast and saturation like C:S, less washed out
- [ ] G4 Depth of field / tilt-shift option for close views
- [ ] G5 Night: warm street lighting pools, lit windows, floodlight glow and bloom
- [ ] G6 Weather: wet surfaces and puddles in rain, snow cover on roofs and ground

## H. UI
- [ ] H1 Consistent C:S-style panel design: header bars, info panels with icons and numbers
- [ ] H2 Info views (overlays): crowd density, transport reach, noise, money heat-map
- [ ] H3 Tooltips with previews and stats for every build item
- [ ] H4 Placement feedback: green/red footprint grid, snapping guides, cost floating by the cursor
- [ ] H5 Notifications as icons above buildings (needs a kiosk, queues, etc.)
- [ ] H6 Main menu / new game screen with club setup
- [ ] H7 Sound effects for UI clicks and building

## I. Gameplay depth (visual side)
- [ ] I1 Matchday: players on the pitch, ball, goal celebrations shown
- [ ] I2 Crowd animation: standing, cheering, scarves, flags waving
- [ ] I3 Stadium construction animation (scaffolding, cranes) instead of instant appearance
