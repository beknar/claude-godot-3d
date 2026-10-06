# claude-godot-3d

A small Godot 4.7 flight game: pilot a comic-book-styled space fighter over endless rolling
hills. Everything in it is made inside the engine or by scripts in this repo: the 3D model,
its textures, the sound effects, the terrain and the visual effects. There are no imported
art assets.

---

## Contents

- [Getting started](#getting-started)
- [How to fly](#how-to-fly)
- [The game](#the-game)
- [Tuning the game](#tuning-the-game)
- [How it's made](#how-its-made)
- [Project layout](#project-layout)
- [Regenerating assets and rendering videos](#regenerating-assets-and-rendering-videos)
- [AI editor integration](#ai-editor-integration)
- [Troubleshooting](#troubleshooting)

---

## Getting started

**Requirements**
- [Godot 4.7](https://godotengine.org/download) (the standard build; .NET isn't needed).
- Any GPU that runs OpenGL 3.3. The project uses the lightweight **GL Compatibility** renderer.
- Optional, only for regenerating assets: [uv](https://docs.astral.sh/uv/) (Python runner).

**Run it**
1. Clone or download this repository.
2. Start Godot, choose **Import**, and select `project.godot`.
3. Press **F5** (Run Project). The flight level is the main scene.

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
- **Engine hum** that rises in pitch and volume with throttle and speed.
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

Key bindings are under **Project → Project Settings → Input Map** (actions starting with `fly_`).

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

### Audio (`game/audio/`, made by `tools/generate_sfx.py`)

All seven sounds are synthesized by a Python script from tones and shaped noise. The loops
repeat without clicks, and Godot detects their loop points automatically.
`game/fighter_audio.gd` blends the engine, wind and afterburner loops by throttle and speed,
and plays the one-shot sounds on the controller's events.

### Effects (`game/fx/`)

- **Jet streams:** particle puffs that start white-hot and fade to blue.
- **Ink outline:** the full-screen outline effect, as a reusable scene.
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
game/                    the playable game
  flight_level.tscn      main scene
  fighter_controller.gd  flight, speed, boost, assists, HUD
  fighter_audio.gd       engine, wind and effect sounds
  fighter_livery.gd      per-level paint scheme
  chase_camera.gd        third-person camera
  window_controls.gd     fullscreen toggle (autoload)
  terrain/               rolling-hills generator and ground shader
  fx/                    exhaust particles, ink outline
  audio/                 generated sound effects
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

# Panel textures -> fighter/textures/*.png (change the seeds in the script for new layouts)
uv run --no-project --with numpy --with pillow python tools/generate_textures.py

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
| Can't resize the game window | The game is running inside the editor's Game tab. Turn off **Embed Game on Next Play**, or press F11 for fullscreen in a standalone run. |
| Mouse doesn't steer | Click inside the game window to capture the mouse (Esc releases it). |
| Steering feels upside down | Tick **Invert Mouse Y** on the `Player` node. |
| Outlines speckle flat surfaces | Keep the camera's **Near** value large (1 m or more); a tiny near plane ruins depth precision. |
