# fly-brain-grok (this branch)

This `fly-brain-grok` branch is the **body** for [github.com/monomyth/fly-brain-grok](https://github.com/monomyth/fly-brain-grok): kinematic grasp of a solid cube (corner/edge pinch), fingertips-down IK, MCP 1.9.

There is **no** MaleCNS / LIF / Brian2 in this app. The controller is an external Python process.

| | |
|---|---|
| Controller | https://github.com/monomyth/fly-brain-grok |
| Distilled `g` + `U` | https://huggingface.co/monomyth/fly-brain-grok |

IPC: `rebot-motionlab-grok-<uid>`. Capture `apply:false` must not steal the live camera.

Build: `bash scripts/swift-local.sh test` then `bash scripts/wrap-debug-app.sh`. Open `dist/ReBot Motion Lab Grok.app`.
