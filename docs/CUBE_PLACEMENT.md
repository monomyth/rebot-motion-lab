# Floor placement and cube size (1.7)

The cube can be placed anywhere on the existing 4 m × 4 m floor where its complete footprint fits and the robot's conservative per-part collision bounds are clear. Placement no longer requires a reachable pickup pose or a radius between 200 and 500 mm.

Cube side length is **10–90 mm inclusive** (1–9 cm). The upper bound matches the fully open gripper; it does not shrink when the hand is currently closed. Rendered and physical cube dimensions change together, and the cube center is placed at `floor_height + side / 2`.

## UI

After **Set up cube**, the X, Y, side, and yaw fields remain available:

- **Apply cube** uses those values to reposition/resize the cube on the floor.
- **Place with mouse** switches to Top view. Click a clear floor point to place the cube using the entered side and yaw. Escape cancels; Shift-drag/right-drag pans and the wheel zooms.
- The size stepper is bounded to 10–90 mm. Out-of-range typed values are rejected when applied.

Edits keep the current arm joints and gripper aperture, preserve the task's other settings, and start a fresh episode. Reset remembers the new cube parameters and restores the configured initial robot pose. Stop motion, external control, and recording before editing. The complete rotated footprint and any configured placement jitter must remain on the floor. Invalid edits preserve the previous cube and episode.

## MCP

Server: `rebot-motion-lab-codex`. The additional tool brings discovery to 24 tools:

```json
{
  "name": "rebot_place_cube",
  "arguments": {
    "x_mm": 450,
    "y_mm": -100,
    "size_mm": 30,
    "yaw_deg": 0
  }
}
```

`x_mm` and `y_mm` are required. Omitting size or yaw preserves the current value. Place/resize clears random placement jitter so resets use the selected position. `rebot_configure_task` also accepts the expanded position and size ranges. `rebot_get_task` advertises floor and side limits; evaluation reports `cube_collider_size_mm` from the actual physics shape.

Reachability and approach clearance are assessed when requesting motion. Accepting a floor location does not claim that the arm can pick up a cube at that location or with every size/approach combination.

## Checks

```sh
bash scripts/swift-local.sh test
bash scripts/build-app.sh ./dist
python3 scripts/verify-cube-edit.py "dist/ReBot Motion Lab Codex.app" work/cube-edit-verification
```

The MCP test verifies 10, 90, and fractional side lengths using actual collider dimensions; distant floor positions; preservation of arm pose and a closed gripper; rejection of invalid dimensions, footprints and overlap without mutation; reset persistence; external ownership; and the existing five-second pickup. Core tests cover footprint/yaw/jitter bounds and ray-plane intersections. Native UI checks cover numeric resizing and mouse placement.
