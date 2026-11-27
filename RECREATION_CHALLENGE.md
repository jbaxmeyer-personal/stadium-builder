# Recreation challenge: famous grounds built with the game's own tools

Each ground was built only with what a player can do (stands, tiers, shapes,
roofs, paint, signs, corners, floodlights, crowd culture, pieces). No special
code. Round 1 graded from memory; round 2 puts a real photo (Wikimedia Commons,
CC BY-SA, used here only as a reference for comparison) next to our v1 and v2
builds, camera matched to the photo. Screenshots: `docs/recreation/`, side by
sides: `docs/recreation/compare/`.

## Round 2: real photo vs our v1 vs our v2

| Ground | v1 | v2 | What v2 fixed | What still gives it away |
|---|---|---|---|---|
| Signal Iduna Park | D+ | C+ | Yellow A-frame pylons outside the roof, one continuous roof ring, rounded corners, white steel trusses on top, glazed facade with the yellow band | Pylons still slimmer and fewer than the real 8; roof sheeting reads as fine noise from the air; the real roof opening is pitch-sized, ours is smaller; seats should be black with yellow blocks (seat patterns exist; now used in v3); no Borusseum/forecourt |
| Anfield | C- | C | White roofs with the long top trusses, the tall Main Stand, glazed and closed roof ends, player banners | The Main Stand's roof should fold down at the ends (a cranked roof shape); its white cladding reads as brick in our closed ends (paint choice); the real ground is a tight rectangle with square corners and no roof ring; terraced streets right up to it |
| Old Trafford | C | B- (v4) | White space-frame roof over a continuous ring, red cladding; v3: 3-tier corners make one continuous bowl (99,750 places), corner walls take the stand's paint | v4: squarer corners (roundness 0.3) and a smaller roof reach make the rectangle. Still: corner roofs lack the space-frame trusses (roof shape not copied to the corners in the script); the real roof is lighter and more open; the grey bays between red panels; the glass corner atrium (now a piece) |
| San Siro | D+ | C+ (v5) | Ramp towers now stand outside the bowl as banded drums; upper tiers close their ends | Read as a tall box of vertical fins, not the low curved stack of open tiers; the giant red box girders; an oval plan. v3 added the "open tiers" facade and box-girder roof supports; v4 has 3-tier rounded corners with the bands wrapping round, so the bowl reads as one curved stack. Still missing: the ramp drums read too small, the real girders cross over the roof diagonally, the low wide proportions |

| Tottenham Hotspur Stadium | C+ | B- (v2) | Oval bowl from tiered rounded corners, grey ring roof with a clear inner strip, dark seats, single-tier home end | v2: split facade (glass skin below, grey tiles above). Still: the real bowl is almost circular (sides bow out); the polished roof rim overhangs the facade |

| Craven Cottage | B- | B- (v2, from the stands) | Classic gable roof on pillars over a low brick stand (heritage facade outside), slim masts, steep modern stand opposite, dark seats | The real Johnny Haynes roof is lower and longer with a cream fascia and the club crest on the gable; the real Riverside stand behind the camera is huge and new; we have no wooden seats; crowd density |

| Allianz Arena | - | C+ (v1, at dusk) | New ETFE cushion finish: a diamond lattice of pillows glowing at night, on an oval bowl with 3-tier rounded corners and a ring roof | The real skin is one smooth inflated tyre that curves in over the top; ours is straight walls with a roof on top. The esplanade and bridge in front; a dusk sky (ours goes to full night) |

What round 2 added to the game (all player tools, not special cases):
A-frame and box-girder pylons with their own paint; roof ends open / closed /
glazed; the "open tiers" facade; ramp and stair towers that stand against the
outside of a stand; memorials and named gates with the player's own words; a
ground sign; floodlight count, height, colour and lamp heads; goal and line
colours; whole-wall murals; copy look from another stand.

New gaps found in round 2 (added to BACKLOG section 12):
- Cranked / folded roof ends (Anfield Main Stand)
- Roof opening size as one setting for a ring roof (Old Trafford, Dortmund)
- Corner atrium pieces (glass corner entrance blocks)
- Oval plan for the whole bowl (San Siro) - partly answered: 3-tier rounded corners now close the bowl
- Corner stands were never limited; the round 1-2 scripts just built them single-tier. Round 3 uses tiered corners
- Metal roof sheeting needs a far-distance LOD so it reads smooth from the air

## Round 1

Grades: how close a fan would say it looks (A = instantly recognisable, F = no).

| Ground | Grade | What works | What's missing (the gaps) |
|---|---|---|---|
| Signal Iduna Park (Dortmund) | C | Steep single-tier south end, yellow steel, filled corners, mast roofs, German crowd | The famous **yellow pylons outside the roof** (8 tall yellow towers holding the roof), a **continuous roof ring** over stands and corners, the **black/yellow facade band**, the Yellow Wall needs **vertical scale** (25k in one stand: our max depth is 12 rows) |
| Anfield (Liverpool) | C- | Huge 3-tier Main Stand towering over the rest, red seats, glass facade, name signs | **Roof heights don't step down** from Main Stand to Kop like the real roofline, the Main Stand roof should **overhang its sides**, the **Kop's sloped roof** and its single huge tier, **Shankly Gates** and the **Hillsborough memorial**, corner infills should be **lower than the sides** |
| Old Trafford (Man United) | C | 3 tiers all round, curved corners, red seats, cantilever roofs, "MANCHESTER UNITED" on a stand | The **red roof masts** are close but the real ones are **one continuous cantilever ring with a single line of trusses**, the **South Stand is lower** (railway line behind it: we need a **railway** neighbour), the **brick and glass East Stand frontage**, **mega-store and statues** forecourt |
| Emirates (Arsenal) | B- | A bowl with rounded corners, translucent roof ring, red seats, player murals on the outside | The real bowl is **one continuous oval** (our corners are separate pieces with **seams**), the **wavy roof edge**, the **glass skin rising in one curve**, a **bridge entrance** over the railway, the **upper tier overhanging the lower tier** |
| San Siro (Milan) | C | Three tiers, red truss roof, spiral ramp towers | The **11 cylindrical ramp towers** wrapping the whole ground (ours sit on concourses and look small), the **roof on four corner towers** with **giant red girders**, the outer **spiral ramp cage** that defines the look, an **oval** bowl |
| La Bombonera (Boca) | B | Three steep stacked tiers on three sides, the flat palcos side, blue and gold, fence, South American crowd | The **"D" shape** (the flat side is the boxes, the others curve), **steepness beyond 40°** (it's near vertical), **murals** painted all over the outside, the **boxes stacked as a vertical wall**, a **tighter fit to the pitch** (no surround) |
| Craven Cottage (Fulham) | B- | Small classic ground, brick main stand with a gable roof, the river, pylons | The **cottage pavilion in a corner** (our clubhouse can't sit in a corner of the bowl), **Johnny Haynes Stand's Archibald Leitch facade** (needs a **heritage brick facade** with arched windows and gables), the **Riverside Stand right on the Thames** |
| Non-league (Ashby Town) | A- | One seated stand, a covered terrace, grass banks, rail, slim masts, clubhouse, tea bar, turnstile hut | **Dugout shelters on the halfway line in the bank**, **hard standing** path round the pitch, **advertising hoardings on the rail**, **a scoreboard on a post**, **perimeter fence with turnstile gate** |

## The gap list this produced (added to BACKLOG.md section 12)

### Shape and structure
1. Continuous bowls: corners that merge seamlessly into the sides (one oval or rounded-rectangle bowl piece), not separate blocks with seams
2. Oval / D-shaped grounds and curved side stands
3. Stand depth beyond 12 rows (big ends: 25-30 rows) and stands taller than the current tier limit
4. Upper tier overhanging the lower tier (cantilevered tier fronts)
5. Corner infills lower than the sides, at their own height
6. Rake above 40° for near-vertical South American stands
7. Pitch tight to the stands (no run-off) and sunken pitches

### Roofs
8. One continuous roof ring over stands and corners (with a single fascia)
9. Roof heights that step between neighbouring stands, with closed side gables
10. Roof structure outside the stand: pylons / masts / towers placed by the player (Dortmund's yellow pylons, San Siro's four towers, Cardiff-style masts)
11. Wavy and curved roof edges
12. Roofs carried by giant external girders (San Siro)

### Facades and outside
13. Heritage brick facade with arched windows, gables and pediments (Leitch style)
14. A glass skin that wraps the whole ground in one curve
15. External ramp towers wrapping the outside of the bowl (San Siro) and stair cores as big visible cylinders
16. Murals painted over the whole outside of a stand (Bombonera)
17. Memorials, gates (Shankly Gates), statues of chosen poses and plaques
18. Bridges over railways/roads to entrances; a railway line as a neighbour

### Pieces placed anywhere
19. Buildings (cottage, clubhouse, scoreboard) placed in a corner of the bowl
20. Dugouts placed into a bank or stand front at the halfway line
21. Scoreboard on a post; hoardings on the rail
22. Hard standing path round the pitch inside the rail

### Seen from the pitch
25. Executive boxes / "palcos" need a pitch-side frontage: rows of glazed boxes with
    balconies and dividers, not a flat painted wall (Bombonera's south side reads as a
    blank blue wall from the centre circle)
26. Upper-tier fronts should show a fascia with lettering/LEDs and the seats behind them
27. Corner stands seen from inside show their stepped outer edge; a continuous bowl needs
    a smooth top edge

### Crowd and life
23. A full Yellow Wall needs a much bigger crowd density on safe standing
24. Giant flag displays sized to a whole stand
