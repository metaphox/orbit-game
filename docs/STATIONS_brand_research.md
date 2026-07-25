# Station operator-brand research

Research date: 2026-07-25. This note records the references behind the station
operator palettes in `tools/station_gen.py`. The four operators, names, palettes,
and marks are original fiction. They are not endorsements and deliberately avoid
the names, silhouettes, flags, and protected marks of the source organisations.

The goal is not to reproduce one historical vehicle. It is to recover several
visual habits from 1970s aerospace and industrial design, then recombine them into
four related but distinguishable manufacturers in the game's universe.

An exact-phrase web search on the research date found no aerospace operator using
any of the four full names. That is an informal fiction-writing collision check,
not legal or trademark clearance.

## Period references and useful lessons

### Shared 1970s aerospace language

- NASA's 1976 [Graphics Standards Manual](https://www.nasa.gov/image-article/nasa-graphics-standards-manual/)
  and the history of the 1975 [NASA logotype](https://www.nasa.gov/general/the-worm-is-back/)
  show how a restrained wordmark, generous empty space, and one assertive signal
  colour can make very complicated hardware feel like one designed system. We use
  that discipline, not either NASA mark.
- Apollo-Soyuz flew in 1975; NASA's [mission history](https://www.nasa.gov/history/astp/kipp.html)
  and [spacecraft account](https://www.nasa.gov/history/the-apollo-soyuz-test-project-success-achieved-for-first-rendezvous-and-docking-of-two-nations-spacecraft-in-space/)
  show a useful common vocabulary of pale insulation, exposed metal, black
  equipment zones, collars, and small high-contrast identifiers.
- NASA's Shuttle history records that the first external tanks were painted white
  before the natural orange-brown spray-on foam was left exposed. That makes
  [the tank material](https://www.jpl.nasa.gov/edu/resources/teachable-moment/navigating-la-with-65000-pounds-of-nasa-space-shuttle-history/)
  a good precedent for treating safety orange as a material/process cue instead
  of generic decoration.
- The official Gerry Anderson account of the *Space: 1999*
  [Eagle Transporter](https://gerryanderson.com/en-us/blogs/blog/space-eagle-transporter-nick-macarty)
  describes an intentionally modular and functional vehicle. Its lesson here is
  exposed load paths and replaceable payload units, not the Eagle's protected
  silhouette or markings.

### Japan: precise, warm, ordered

Bandai Namco's retrospective dates *Space Battleship Yamato* to 1974 and calls out
its unusually precise mechanical design in the company's
[official release](https://www.bandainamco.co.jp/releases/images/3/43031.pdf).
Period Japanese spacecraft fiction often balanced warm light hulls, very dark
technical zones, a decisive warm accent, and unusually ordered panel detail. For
an original civilian operator, we retain that warm/cool balance and precision but
discard naval forms, character colours, and recognizable insignia.

### China: faceted alloy, lacquer, sparse apertures

China's first satellite, Dongfanghong-1, launched in 1970 according to the
[China National Space Administration](https://www.cnsa.gov.cn/n6758968/n6758972/c10004149/content.html).
The [National Museum of China model](https://www.chnmuseum.cn/zj/zjdt/202203/t20220303_254147.shtml)
and its [construction note](https://www.chnmuseum.cn/zj/jzrgs/202203/t20220303_254149.shtml)
show a strongly faceted metallic body, a dark equatorial equipment band, and
sparse appendages. That suggests satin celadon-grey alloy, ink-black hardware,
brass thermal detail, and one cinnabar identifier. The palette is an industrial
composite, not a flag treatment.

### United States: aerospace enamel, exposed process colour

The 1970s Shuttle programme paired cool white thermal surfaces, black anti-glare
and thermal areas, bare alloy, and process-derived orange foam. The graphic system
above adds large, legible identifiers and safety zoning. The fictional American
operator therefore uses cool aerospace white, graphite, midnight-blue collector
glass, and a restrained safety-orange accent with brushed-metal response.

### Germany: modular laboratory, quiet product discipline

ESA's history records the 1973 Spacelab agreement and the German-led ERNO team's
work; the [1978 Bremen engineering model](https://www.esa.int/ESA_Multimedia/Images/2013/11/Spacelab_module_Engineering_Model_Bremen_1978)
and ESA's [construction history](https://www.esa.int/About_Us/50_years_of_ESA/Building_and_flying_Spacelab)
show a rational modular laboratory rather than a heroic vehicle. In parallel,
Dieter Rams' period product work favoured reduction, order, and restrained colour;
Vitsœ summarises that philosophy as
[good design](https://www.vitsoe.com/us/about/good-design), while
[MoMA's collection](https://www.moma.org/artists/8451-dieter-rams)
documents the material vocabulary. The fictional German operator translates this
into warm-grey powder coat, graphite phosphate, petrol collector glass, a strict
grid, and one ochre signal colour. It does not reproduce a Braun, Vitsœ, ERNO,
or ESA mark.

## Synthesis rules

1. Every operator uses the same five semantic roles: **hull**, **structure**,
   **solar**, **accent**, and **light**. Geometry asks for a role; the selected
   brand supplies its material.
2. Colour and finish work together. A palette is not complete without its surface
   response: ceramic enamel, anodising, black oxide, brushed alloy, collector
   glass, lacquer, or powder coat.
3. Accent colour identifies an operator or a serviceable/safety zone. It does not
   wash an entire pressure vessel.
4. Marks are built from two to four primitive shapes and remain readable at module
   scale. No mark uses a national flag, star field, NASA orbit, NASA worm, ESA
   symbol, or a source-fiction silhouette.
5. Brand selection must not change station topology, random-number consumption,
   collision results, organisation score, or connectivity. At this stage it is a
   deterministic render/material parameter only.

## Original operators

The design specification, exact colours, material response, logo geometry, CLI
contract, and acceptance criteria live in [STATIONS.md](STATIONS.md#8-operator-brands-and-material-language).
Future brand-specific structure may build on these visual languages only after it
is documented there as a separate generator phase.
