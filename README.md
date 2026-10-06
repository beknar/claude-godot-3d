# claude-godot-3d

A small Godot 4.7 flight game: pilot a comic-book-styled space fighter over endless rolling
hills. A second level lets you play as a winged cyborg who can walk, run and fly, and a
third walks a woman through a city street at dusk.
Almost everything is made inside the engine or by scripts in this repo: the 3D models, their
textures, skeletons and animations, the sound effects, the terrain, the city and the visual
effects. The imported assets are the engine hum, a sound effect from Pixabay (see
[Credits](#credits)), and the woman figure, a single static mesh that the repo's scripts rig
and animate.

---

## Contents

- [Getting started](#getting-started)
- [How to fly](#how-to-fly)
- [The game](#the-game)
- [The winged cyborg level](#the-winged-cyborg-level)
- [The city street level](#the-city-street-level)
- [Tuning the game](#tuning-the-game)
- [How it's made](#how-its-made)
- [Project layout](#project-layout)
- [Regenerating assets and rendering videos](#regenerating-assets-and-rendering-videos)
- [AI editor integration](#ai-editor-integration)
- [Troubleshooting](#troubleshooting)
- [Credits](#credits)

---

## Getting started

**Requirements**
- [Godot 4.7](https://godotengine.org/download) (the standard build; .NET isn't needed).
- Any GPU that runs OpenGL 3.3. The project uses the lightweight **GL Compatibility** renderer.
- Optional, only for regenerating assets: [uv](https://docs.astral.sh/uv/) (Python runner),
  and [Blender](https://www.blender.org/) 4.x or 5.x to re-rig the woman figure.

**Run it**
1. Clone or download this repository.
2. Start Godot, choose **Import**, and select `project.godot`.
3. Press **F5** (Run Project). The flight level is the main scene.
4. To play the winged cyborg instead, open `game/person_level.tscn` and press **F6**
   (Run Current Scene). For the city street, open `game/fig1_level.tscn`.

The game opens in a 1152×648 window that can be resized or made fullscreen. The editor runs
the game inside its **Game** tab by default; to get a separate, freely resizable window, turn
off **Embed Game on Next Play** in that tab's toolbar.

---

## How to fly

| Input | Action |
|---|---|
| **Mouse** | Point the nose (up/down and left/right) |
| **Arrow keys** | Point the nose (keyboard alternative) |
| **A / D** | Roll left / right |
| **W / S** (or **E / Q**) | Throttle up / down; the throttle stays where you leave it |
| **Shift** (hold) | Afterburner |
| **Space** (hold) | Air brake |
| **Esc** | Release the mouse; click in the window to capture it again |
| **F11** or **Alt+Enter** | Toggle fullscreen |

**Tips**
- The ship always flies forward. You steer where the nose points and set your speed with
  the throttle.
- Let go of A/D and the wings level themselves, even from upside down.
- Diving gains speed and climbing loses it, so trade height for speed before a boost.
- The afterburner tank lasts 4 seconds and refills in 8. If it runs dry, release Shift and
  press it again to relight once there's enough fuel.

---

## The game

You fly a twin-engine fighter over a 4 km × 4 km landscape of grassy rolling hills under a
hazy daytime sky.

**On-screen readout** (top-left)
- **SPEED** and **ALT** (height above the ground directly below you).
- **THROTTLE** bar and percentage.
- **BOOST** bar (afterburner fuel).
- Status words: **AFTERBURNER**, **AIR BRAKE** and **PULL UP** (when below 25 m).
- A reminder of the controls.

**Speed system**
| | Speed |
|---|---|
| Throttle 0% | 30 |
| Throttle 100% | 110 |
| Afterburner | up to 175 |
| Air brake | drops quickly to 30, without moving the throttle |

The ship accelerates and slows gradually toward whatever the throttle asks for.

**Safety assists**
- **Ground clearance:** the ship can't fly into the hills. It stays at least 8 m above them
  and lifts its nose when skimming the ground.
- **Ceiling:** maximum altitude is 700 m.
- **Map edge:** fly more than 1.2 km from the centre and the ship is gently turned back
  toward the middle, so you never see the edge of the world.

**Sound**
- **Engine hum:** a deep, wide spaceship drone that rises in pitch and volume with throttle
  and speed. It's mostly bass, so it comes through best on headphones or decent speakers.
- **Wind** that grows with airspeed and louder with the air brake out.
- **Afterburner:** an ignition thump, then a crackling roar while it burns.
- **Air brake:** a clunk followed by a falling hiss.
- **Empty tank:** a buzz when you press Shift with too little fuel.
- **Low-altitude warning:** a repeating double beep.

**Look**
- The fighter is drawn like the comic illustration it's based on: ink-outlined panels, flat
  two-tone shading and bold black outlines.
- In the flight level it wears a dark gunmetal and orange paint scheme so it stands out
  against the sky and hills.
- Glowing blue jet streams trail from both engines and swell on afterburner.

---

## The winged cyborg level

`game/person_level.tscn` puts you in control of a half-human, half-mechanical girl with
great black mechanical wings, built after a reference illustration: pale face and glowing
green eyes, shaggy black hair, blue-steel armour over a ribbed undersuit, clawed gunmetal
hands and a bronze core on her chest. She stands on a 1.6 km landscape of gentler hills.

| Input | Action |
|---|---|
| **W A S D** | Move (relative to where the camera looks) |
| **Shift** (hold) | Run; in flight, fly fast and glide |
| **Space** | Jump; press again in mid-air to spread the wings and fly; hold while flying to climb |
| **C** or **Ctrl** (hold) | Descend while flying; touch the ground to land |
| **F** | Take off from the ground, or fold the wings and drop while flying |
| **Mouse** | Orbit the camera; **wheel** zooms |
| **Esc** | Release the mouse; click to capture it again |

**How she moves**
- On the ground she walks at 1.8 m/s and runs at 6 m/s. The animation speeds up with her, so
  her feet don't slide.
- In flight she hovers upright with fast wingbeats, leans into level flight as she speeds up
  (about 9 m/s), and glides with her wings spread at full speed (20 m/s, holding Shift). She
  banks through turns and tips her nose up when climbing.
- Her wings fold against her back whenever she isn't flying. When she lands, or drops out
  of flight with F, they fold over about a second: shoulders down, then forearms, then
  hands, with the feathers collapsing into a stack down her back. They spread again,
  faster, on take-off.
- The status line shows what she's doing (standing, walking, running, jumping, falling,
  hovering, flying, gliding), her speed and her height above the ground.
- Like the flight level, she's turned back before she reaches the edge of the map.

---

## The city street level

`game/fig1_level.tscn` puts you on the sidewalk of a city street at dusk, as a woman in a
black dress and heels (`fig1/`).

| Input | Action |
|---|---|
| **W A S D** | Walk (relative to where the camera looks) |
| **Shift** (hold) | Run |
| **Space** | Jump |
| **Mouse** | Orbit the camera; **wheel** zooms |
| **Esc** | Release the mouse; click to capture it again |

- **The street:** a two-way street with parking lanes, centre and lane markings and a zebra
  crossing. It has kerbed sidewalks, which she steps up onto, and rows of buildings with lit
  windows and glowing shopfronts. Street lights along both sides cast warm pools of light.
- **Traffic:** parked cars line the kerbs, and cars drive both ways with their headlights on.
  They brake for her if she steps into their lane, and for the car ahead.
- **The camera:** keeps itself in front of walls, so it doesn't end up inside a building.

---

## Tuning the game

Most behaviour is set with values you can change in Godot's **Inspector**, no coding needed.
Open `game/flight_level.tscn` and select:

| Node | What you can change |
|---|---|
| `Player` | Speeds, acceleration, throttle rate, boost tank size and recharge, mouse sensitivity, **Invert Mouse Y**, turn and roll rates, wings-level assist strength, ground clearance, warning height, ceiling, map radius |
| `Player/Audio` | Volume and pitch ranges for the engine, wind and afterburner |
| `Player/Livery` | The paint scheme: hull, accent, trim and seam colours |
| `Terrain` | Map size, mesh detail, hill height, random seed, hill frequency and roughness, valley shape. The hills regenerate live in the editor. |
| `ChaseCamera` | Follow distance and height, look-ahead, smoothing, whether it rolls with the ship, field of view and the extra FOV on boost |
| `ChaseCamera/InkOutline` | Outline colour, thickness, sensitivity and fade distance (material `game/fx/ink_outline_flight.tres`) |

In `game/person_level.tscn`:

| Node | What you can change |
|---|---|
| `Player` | Walk and run speeds, jump height, gravity, stride lengths (for foot sync), flight speeds, climb rate, ceiling, map radius, how far she leans and banks in flight, turning speed, how long the wings take to fold and spread |
| `Camera` | Distance on the ground and in flight, zoom range, mouse sensitivity, **Invert Mouse Y**, pitch limits, follow smoothing |
| `Camera/InkOutline` | Outline settings for close-ups (material `game/fx/ink_outline_person.tres`) |

In `game/fig1_level.tscn`:

| Node | What you can change |
|---|---|
| `Street` | Street length, lane, parking and sidewalk widths, kerb height, random seed (building layout and colours), street-light spacing, number of parked cars, cars per lane, crossing position. The street regenerates live in the editor. |
| `Player` | Walk and run speeds, acceleration, air control, jump height, gravity, jump grace and buffer times, landing threshold, stride lengths |
| `Camera` | As in the cyborg level, plus wall avoidance |

Key bindings are under **Project → Project Settings → Input Map** (actions starting with
`fly_` for the fighter and `move_` for the winged cyborg and the woman).

---

## How it's made

### The fighter model (`fighter/fighter.tscn`)

The model was built to match a reference illustration of a sci-fi fighter. It's about **2,500
triangles**, made entirely from Godot's built-in shapes.

- **Hull parts** (fuselage, chin, canopy, spine hump, wing arms) are each the *intersection* of
  three extruded outlines: a side view, a top view and a front view. This gives hard-edged,
  faceted panels like the illustration, and a part can be reshaped by editing its outlines.
- **Round parts** (engines, cowls, intake lips, nozzles, cannons, pipes) are cylinders and
  rings, kept low-poly.
- **Small detail** that would cost many triangles is *drawn* instead of modelled: vents,
  hatches, raised and recessed panels, markings and the canopy frames are painted by the
  shaders with fake relief (bump mapping).
- **One model, used everywhere:** `fighter.tscn` is shared by the game, the showcase and the
  turntable. The flight level recolours its copy without changing the original.

### Textures (`fighter/textures/`, made by `tools/generate_textures.py`)

A Python script paints panel layouts in the illustration's style. It splits rectangles into
irregular plates outlined in ink, then adds inset plates, nested panels, notches, rounded
slots, slatted vents, round hatches and striped warning decals.

Each texture packs four maps into its colour channels: which plates are inset, where the ink
lines are, the per-plate shading and decal mask, and a height map. Colours are chosen in the
material, which is how the same texture can be repainted. The model has no UV unwrap, so the
hull shader projects the texture onto each part from three directions. The engines wrap
theirs around the cylinder.

### Shading and outlines

- **Cel lighting:** each surface is either fully lit or in a cool blue-grey shadow, with a
  narrow soft edge, like the illustration's flat shading.
- **Ink outlines:** a full-screen effect reads the depth buffer and draws black lines where
  the surface jumps (silhouettes) or turns sharply (creases). It measures the depth buffer's
  precision at each pixel so flat surfaces don't get false lines.
- **Shared shader code** lives in `fighter/materials/detail_lib.gdshaderinc`.

### Terrain (`game/terrain/`)

`RollingHillsTerrain` builds a smooth hill mesh from layered noise, plus an exactly matching
collision shape. It regenerates whenever a setting changes, even in the editor. The ground
shader blends grass that dries out with height, dirt on slopes and rock on the steepest
faces, and the sky's haze hides the edge of the map. **Bake Mesh To File** on the Terrain node
saves the hills as a standalone mesh.

### Flight (`game/fighter_controller.gd`)

An arcade flight model:
- The mouse sets turn rates, smoothed so steering feels weighty, and A/D sets the roll rate.
- Speed chases the throttle with finite acceleration and drag. Diving and climbing add and
  subtract speed.
- The afterburner has a fuel tank and a relight rule.
- It also handles the ground, ceiling and map-edge assists, and writes the HUD text.
- It sends events (boost started/ended/denied, brake started/ended, low-altitude warning)
  that the audio listens to.

### Camera (`game/chase_camera.gd`)

The camera follows a smoothed copy of the ship's orientation. It rolls and loops with the
ship without ever flipping, and widens its field of view on boost.

### Audio (`game/audio/`, made by `tools/generate_sfx.py` and `tools/make_engine_loop.py`)

Six of the seven sounds are synthesized by a Python script from tones and shaped noise. The
loops repeat without clicks, and Godot detects their loop points automatically.
The engine hum is a recording (see [Credits](#credits)). `tools/make_engine_loop.py` trims it,
crossfades its ends into a seamless 45-second loop and saves it as `engine_loop.ogg`.
`game/fighter_audio.gd` blends the engine, wind and afterburner loops by throttle and speed,
and plays the one-shot sounds on the controller's events.

### The winged cyborg (`person/`, built by `tools/build_person.gd`)

The character is generated by a script that runs inside Godot, so it can be rebuilt and
changed like the rest of the project. About **19,600 triangles** and 153 bones.

- **Skeleton:** hips, spine, chest, neck and head; shoulders, arms and hands; legs, feet and
  toes; three bones per wing (shoulder, elbow, wrist); and a small bone for every
  feather, so the wings can fold neatly.
- **Body:** each part is a loft of cross-sections, much like the fighter's outlines. The armour
  plates are thick curved shells: breastplate, back plate, layered abdomen bands, belt, hip
  plates, pauldrons, vambraces, thigh plates, pointed knee guards, shin guards and boots.
  Ball joints sit at the shoulders, elbows, knees and ankles, and the hands end in long claws.
- **Skinning:** being a machine, most parts follow a single bone rigidly, which avoids the
  pinching soft skin suffers at joints. Only the undersuit around her waist blends between
  the spine bones, so her torso bends smoothly.
- **Head and hair:** a shaped head with a small chin and nose, and about 45 tapered locks of
  hair (bangs, side locks, crown, shaggy back and a few windblown tufts), each pushed clear
  of the skull.
- **Wings:** a jointed metal frame carrying about 50 feather cards per wing: primaries,
  secondaries, tertials and two rows of coverts.
- **Textures and shading** (`tools/generate_person_textures.py`, `person/materials/`):
  - The armour uses the fighter's panel style, with larger plates. The undersuit is ribbed
    with cable grooves, and the feathers are jagged metal blades with torn edges.
  - The model's texture coordinates are laid out in metres, so panel lines and bumps stay
    fixed to the surface as the limbs move.
  - Her face (eyes, irises that glow faintly, lashes, brows, lips and blush) is drawn by the
    skin shader rather than painted into a texture, so it stays sharp up close.
  - Everything uses the same two-tone cel lighting as the fighter, with a cool metallic rim.
- **Animations:** idle, walk, run, fall, hover, fly and glide, all looping and generated from
  gait functions. The glide reproduces the illustration's pose.
  - `fold_wings` folds the wings like a bird's, in a Z against her back, while each feather
    turns on its own bone.
  - In-game, `PersonController` (`game/person_controller.gd`) blends the clips with an
    AnimationTree by speed and state. It plays `fold_wings` forward on landing and
    backward on take-off, on a layer that affects only the wings.

### The woman figure (`fig1/`) and the city street (`game/city/`)

The figure started as `fig1/woman-model.glb`: one static textured mesh, 1 unit tall, with no
skeleton. Two scripts turn it into an animated character:

1. **`tools/rig_fig1.py`** (run in Blender):
   - Scales her to 1.70 m and places a 21-bone humanoid skeleton at joint positions
     measured from slices of the mesh. She stands with one leg angled out, so the joints
     follow her actual limbs rather than a mirrored template.
   - Binds the mesh with Blender's automatic weights and exports `fig1/woman_rigged.glb`.
2. **`tools/build_fig1.gd`** (run in Godot):
   - Turns her to face the same way as the project's other characters and rebuilds the
     skeleton in the same convention as the cyborg's.
   - Straightens her stance into a neutral standing pose.
   - Generates idle, walk (a heels walk with a sway of the hips), run, jump, fall and a
     landing crouch.

`WalkerController` (`game/walker_controller.gd`) blends the clips by speed, by vertical speed
in the air, and with a landing crouch on hard landings.

`CityStreet` (`game/city/city_street.gd`) builds the street from its settings:
- road segments, sidewalks, buildings, street lights and their collision
- road, sidewalk and facade shaders that draw markings, paving slabs, windows and
  shopfronts from world position, so nothing needs UVs or textures
- cars (`StreetCar`, `game/city/street_car.gd`): simple procedural models that park or drive
  their lane

### Effects (`game/fx/`)

- **Jet streams:** particle puffs that start white-hot and fade to blue.
- **Ink outline:** the full-screen outline effect, as a reusable scene. Each level tunes it
  through its own material; the winged cyborg's version only inks strong edges, because a
  camera a few metres from a small figure would otherwise ink every polygon edge.
- **Sky:** the space sky in the showcase is a procedural starfield shader.

---

## Project layout

```
fighter/                 the fighter model and its look
  fighter.tscn           the model (shared by every scene)
  fighter_showcase.tscn  posed like the reference illustration
  turntable.tscn/.gd     10-second rotating view for videos
  materials/             shaders and materials
  textures/              generated panel textures (+ colour previews)
fig1/                    the woman figure
  woman-model.glb        the source model (static mesh)
  woman_rigged.glb       the same mesh, skinned by tools/rig_fig1.py
  fig1.tscn              skeleton, mesh, animation player (generated by tools/build_fig1.gd)
person/                  the winged cyborg (generated by tools/build_person.gd)
  person.tscn            skeleton, skinned meshes, animation player
  person_showcase.tscn   the model on its own, for close-ups
  person_animations.tres idle, walk, run, fall, hover, fly, glide
  meshes/                body, hair and wing meshes
  materials/             armour, skin/face, hair and feather shaders and materials
  textures/              generated armour, undersuit and feather textures (+ previews)
game/                    the playable game
  flight_level.tscn      main scene
  fighter_controller.gd  flight, speed, boost, assists, HUD
  fighter_audio.gd       engine, wind and effect sounds
  fighter_livery.gd      per-level paint scheme
  chase_camera.gd        third-person camera
  person_level.tscn      the winged cyborg's level
  person_controller.gd   walking, running, jumping, flying, animation blending, HUD
  orbit_camera.gd        mouse-orbit camera (cyborg and city levels)
  fig1_level.tscn        the city street level
  walker_controller.gd   walking, running, jumping, animation blending, HUD
  city/                  street generator, procedural cars, road/sidewalk/facade shaders
  window_controls.gd     fullscreen toggle (autoload)
  terrain/               rolling-hills generator and ground shader
  fx/                    exhaust particles, ink outline
  audio/                 sound effects (generated, plus the engine-hum loop)
tools/                   asset generators and helper scripts (ignored by Godot)
addons/godot_ai/         AI editor integration plugin (third party, MIT)
```

---

## Regenerating assets and rendering videos

The asset generators need [uv](https://docs.astral.sh/uv/); `godot` below means your Godot 4.7
executable.

```sh
# Sound effects -> game/audio/*.wav
uv run --no-project --with numpy python tools/generate_sfx.py

# Engine hum -> game/audio/engine_loop.ogg. Needs the source MP3 in tools/source_audio/
# (not in the repo; download it from the link under Credits).
uv run --no-project --with numpy --with imageio-ffmpeg python tools/make_engine_loop.py

# Panel textures -> fighter/textures/*.png (change the seeds in the script for new layouts)
uv run --no-project --with numpy --with pillow python tools/generate_textures.py

# The woman figure: rig in Blender (4.x or 5.x), then build the Godot scene and animations.
# Let the editor import fig1/woman_rigged.glb (focus it) before running the second step.
blender -b --factory-startup -P tools/rig_fig1.py
godot --headless --path . --script tools/build_fig1.gd

# The winged cyborg: textures, then the model, skeleton and animations -> person/
uv run --no-project --with numpy --with pillow python tools/generate_person_textures.py
godot --headless --path . --script tools/build_person.gd

# Triangle count of the fighter, per part
godot --headless --path . --script tools/count_triangles.gd

# A 1080p still of any scene at a given frame
tools/render_frame.sh res://fighter/fighter_showcase.tscn 5 out.png

# A 10-second turntable video: record frames with Godot's Movie Maker, then encode
godot --path . --write-movie frames/frame.png --fixed-fps 60 --quit-after 600 res://fighter/turntable.tscn
ffmpeg -framerate 60 -i frames/frame%08d.png -c:v libx264 -crf 18 -pix_fmt yuv420p turntable.mp4
```

Movie Maker records at the project's window size (1152×648). For 1080p, temporarily set the
base viewport size to 1920×1080; `tools/render_frame.sh` shows how, using an `override.cfg` it
removes afterwards. Rendered videos (`*.mp4`, `*.avi`) are ignored by git.

---

## AI editor integration

`addons/godot_ai` is the [godot-ai](https://github.com/hi-godot/godot-ai) plugin. It runs an
MCP server that lets AI coding assistants such as Claude Code inspect and edit the open
project, run the game and take screenshots. This project was built that way.

To use it:
1. Enable it under **Project → Project Settings → Plugins**.
2. Click **Configure** next to your assistant in the Godot AI dock (it needs `uv` installed).

The game doesn't need it to play. `CLAUDE.md` holds the working notes for Claude Code.

---

## Troubleshooting

| Problem | Fix |
|---|---|
| No sound | Movie Maker mode is on (the film-strip button at the editor's top right). It silences audio and records every run to a video file. Turn it off. |
| Game doesn't resize with the window | The game is running inside the editor's Game tab, which by default keeps it at a fixed 1152×648. In the Game tab's **⋮** menu, choose **Stretch to Fit** (or **Keep Aspect Ratio**) under embedded window sizing. Or turn off **Embed Game on Next Play** to get a separate, freely resizable window (F11 for fullscreen). |
| Mouse doesn't steer | Click inside the game window to capture the mouse (Esc releases it). |
| Steering feels upside down | Tick **Invert Mouse Y** on the `Player` node. |
| Outlines speckle flat surfaces | Keep the camera's **Near** value large (1 m or more); a tiny near plane ruins depth precision. |
| Close-ups of a character look like a wireframe | The outline material is tuned for distant objects. Use `game/fx/ink_outline_person.tres` (higher crease threshold) on cameras that get close. |

---

## Credits

- **Engine hum** (`game/audio/engine_loop.ogg`): ["Spaceship hum low frequency"](https://pixabay.com/sound-effects/film-special-effects-spaceship-hum-low-frequency-296518/)
  by AudioPapkin, used under the [Pixabay Content License](https://pixabay.com/service/license-summary/).
  It is trimmed and looped for this game; it isn't offered here as a standalone sound.
- **AI editor plugin** (`addons/godot_ai/`): [godot-ai](https://github.com/hi-godot/godot-ai), MIT licence.
