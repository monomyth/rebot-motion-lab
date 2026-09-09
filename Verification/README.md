# Verification record

The application source was verified locally with Apple Swift 6.3.3 on Intel macOS 26.6.2 before the first public release.

- **27 Swift Testing tests passed:** complete gripper floor contact, swept motion, kinematics, bounds, malformed inputs, reference completeness, trajectory round trips, STL preservation, playback timing, and MCP protocol/IPC.
- **Native smoke checks passed:** folded startup/reset, scene and TCP agreement, manual controls, IK, playback/pause/resume/completion, presets, scene reuse, trajectory serialization, native font shortcuts, reference views, MCP control state, and private-path masking in both MCP configuration formats.
- **Nine MCP integration groups passed** against an isolated native application, covering all 12 tools and both resources in 1.5. Version 1.6 adds cube, grasp, level IK, capture, and servo tools (18 total); re-run `python3 scripts/test-mcp.py` after packaging.
- **Native slider sample:** 100 action/binding updates over 2.07 seconds, 119 scene updates (~58/s), 0 lagging frames, 0 main-model notifications, and 22 actual-position readout notifications.

Files:

| File | Evidence |
| --- | --- |
| `native-smoke.txt` | Native app check results |
| `mcp-integration.json` | MCP integration check groups |
| `manual-motion.json` | Manual slider input and scene-update samples |
| `performance-before.json` / `performance-after.json` | Earlier v1.0/v1.1 playback samples |

Scene-update counts are not GPU presentation FPS. The packaged universal app was locally executed on Intel; its Apple silicon executable was cross-compiled. The minimum deployment target, macOS 14, was not separately tested locally. Current CI results are available in [GitHub Actions](https://github.com/monomyth/rebot-motion-lab/actions).

The unified web source also passed TypeScript checks, scoped lint, kinematics/STL integrity checks, complete-finger floor checks, and the Vinext production build locally with Node.js 26.7. CI separately checks the web project on Linux with Node.js 24.
