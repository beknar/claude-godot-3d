# claude-godot-3d

A small Godot 4.7 flight game featuring a comic-book-styled space fighter, built entirely
inside the engine: the model, textures, sound effects and terrain are all generated —
there are no imported art assets.

Turntable video: [fighter_turntable_detailed.mp4](fighter_turntable_detailed.mp4)

## Features

- **The fighter** — modelled from CSG and primitive shapes (~1,900 triangles), with procedurally
  painted panel textures, bump-mapped vents/hatches/markings, two-tone cel lighting and
  screen-space ink outlines.
- **Rolling-hills terrain** — 4 km noise-generated landscape with matching collision, regenerated
  live in the editor when its settings change.
- **Flight model** — mouse-aimed 6-DOF arcade flight with roll, throttle, a limited recharging
  afterburner, an air brake, dive/climb speed changes and a terrain-clearance assist.
- **Audio** — synthesized engine, wind, afterburner, air-brake and warning sounds that follow
  throttle and speed.
- **Effects** — particle jet streams, chase camera with speed FOV, starfield sky.

## Running

1. Install [Godot 4.7](https://godotengine.org/download) (standard build).
2. Open `project.godot` in the editor and press **F5**.

The project uses the GL Compatibility renderer, so it runs on most hardware.

## Controls

| Input | Action |
|---|---|
| Mouse (or arrow keys) | Point the nose |
| A / D | Roll left / right |
| W / S (or E / Q) | Throttle up / down |
| Shift | Afterburner (limited, recharges) |
| Space | Air brake |
| Esc | Release the mouse (click to recapture) |
| F11 / Alt+Enter | Toggle fullscreen |

## Scenes

| Scene | Purpose |
|---|---|
| `game/flight_level.tscn` | The playable level (main scene) |
| `fighter/fighter_showcase.tscn` | The fighter posed like the reference illustration |
| `fighter/turntable.tscn` | 10-second rotating view, used to render the turntable videos |
| `fighter/fighter.tscn` | The model itself, shared by all of the above |

## Regenerating assets

The `tools/` folder holds the generators (requires [uv](https://docs.astral.sh/uv/)):

```sh
uv run --no-project --with numpy python tools/generate_sfx.py                    # game/audio/*.wav
uv run --no-project --with numpy --with pillow python tools/generate_textures.py # fighter/textures/*.png
godot --headless --path . --script tools/count_triangles.gd                      # model triangle count
tools/render_frame.sh res://fighter/fighter_showcase.tscn 5 out.png              # 1080p still
```

## Editor AI integration

`addons/godot_ai` is the [godot-ai](https://github.com/hi-godot/godot-ai) MCP plugin (MIT), which
lets AI coding assistants such as Claude Code inspect and edit the open project. Enable it under
**Project → Project Settings → Plugins** and use its dock to connect a client. It is not needed
to play the game.

## Videos

- `fighter_turntable_detailed.mp4` — current look (reshaped canopy, wings, engines and spine)
- `fighter_turntable_textured.mp4` — textures and outlines on the earlier shape
- `fighter_turntable_compare.mp4` — triangle optimisation before/after
- `fighter_turntable.mp4`, `fighter_turntable_optimized.mp4` — earlier versions
