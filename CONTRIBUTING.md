# Contributing

Thanks for helping improve ReBot Motion Lab. Start with a focused issue or pull request that describes the behavior you want to change.

## Set up

For the native app and MCP, use macOS 14+ and Swift 6 through Xcode or Apple Command Line Tools. Clone the repository and follow the [build instructions](README.md#build-from-source). All model assets are included; there are no third-party Swift packages to resolve.

For web work, use Node.js 22.13+ and run `npm ci` from `web/`. Validate with `npm run typecheck`, `npm run lint`, `npm test`, and `npm run build`.

## Report a problem

Include the app version, macOS version, Intel/Apple silicon architecture, and a short sequence of steps. For motion problems, attach an exported example trajectory when it helps. For actuator-reference corrections, link the relevant primary source and identify the hardware, firmware, or SDK version.

Do not include local MCP configuration containing personal filesystem paths, credentials, or unrelated logs. A minimal example is easier to reproduce.

## Make a change

- Keep changes focused and explain the user-visible result.
- Preserve joint order, units, bounds validation, and playback interpolation. During slider or numeric drag, the rendered pose must follow the control immediately; do not add a manual-motion filter or republish the full app model on every tick.
- Keep animation off SwiftUI's full-view update path; use `applyPose` for interactive edits and the existing scene clock for playback.
- Add meaningful tests for motion, kinematics, protocol, or validation behavior that changes. Documentation-only edits do not need a full app build.
- Preserve third-party asset notices and source attribution. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

Run the relevant checks before opening a pull request:

```sh
bash scripts/swift-local.sh test
bash scripts/build-app.sh ./dist
```

For UI or MCP changes, also run the applicable native checks in [Development](docs/DEVELOPMENT.md). Include what you tested and any limitations in the pull request description. Visual changes benefit from a screenshot of the app itself.

Contributions to the application's code and original documentation are provided under its MIT license. Separately licensed model assets retain their original terms.
