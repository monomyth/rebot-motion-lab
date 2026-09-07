# Third-party notices

The root [MIT License](LICENSE) applies to the ReBot Motion Lab application code, build scripts, and original documentation. The components below retain their own notices and licenses.

| Component | Location | License |
| --- | --- | --- |
| B601-DM URDF and STL model assets | `Sources/RobotCore/Resources/model/{urdf,meshes}/` and `web/public/model/{urdf,meshes}/` | CERN-OHL-W-2.0 |
| Mechanical JSON conversion of the URDF | `Sources/RobotCore/Resources/model/model.json`, `web/public/model/model.json`, and `web/lib/model.json` | CERN-OHL-W-2.0 |
| Derived floor-contact support vertices | `Sources/RobotCore/Resources/model/floor-hulls.json` and `web/lib/floor-hulls.json` | CERN-OHL-W-2.0 |
| MotorBridge-derived actuator metadata | Relevant entries in the native resources and `web/lib/actuators.json`, `web/public/B601-DM-actuator-settings.md` | MIT; original notice retained |

## Robot model

Source: [Seeed-Projects/reBot-DevArm, revision c9b893aa26c7d89019dd3d0a28ff8f6a7d47ccf9](https://github.com/Seeed-Projects/reBot-DevArm/tree/c9b893aa26c7d89019dd3d0a28ff8f6a7d47ccf9).

The URDF and STL files are retained verbatim. `model.json` was mechanically converted from the URDF on September 6, 2026; it remains under the model's CERN-OHL-W-2.0 license. The source URDF is included beside the conversion. Floor-contact support vertices are mechanically derived convex hulls of the same geometry. Runtime vertex indexing changes the in-memory rendering representation, not the bundled source files.

- [Model notice](Sources/RobotCore/Resources/model/NOTICE.txt)
- [Complete CERN-OHL-W-2.0 license](Sources/RobotCore/Resources/model/LICENSE.txt)
- [Upstream license at the pinned revision](https://github.com/Seeed-Projects/reBot-DevArm/blob/c9b893aa26c7d89019dd3d0a28ff8f6a7d47ccf9/LICENSE)

The application's MIT license does not replace these terms. Preserve the model notice and license when distributing the bundled assets or their modified versions.

## Actuator metadata

MotorBridge source: [motorbridge/motorbridge, revision c48ebc4b2f250aa1f411a580d9d7b626e187040f/motor_vendors/damiao](https://github.com/motorbridge/motorbridge/tree/c48ebc4b2f250aa1f411a580d9d7b626e187040f/motor_vendors/damiao).

The retained notice is [MOTORBRIDGE-LICENSE.txt](Sources/RobotCore/Resources/MOTORBRIDGE-LICENSE.txt), copyright © 2026 motorbridge. Register descriptions and reference material also cite the inspected Seeed SDK, model catalog, and Damiao protocol documentation directly. Source revisions, reviewed versions, and known mismatches are listed in the [actuator reference](Sources/RobotCore/Resources/B601-DM-actuator-settings.md).

Product names identify the hardware and software being documented. No affiliation or endorsement is implied.

## Web dependencies

The web UI uses React, Three.js, Vinext, shadcn components, and the other dependencies pinned in `web/package-lock.json`. Those packages retain their distributed licenses; see their package notices when redistributing dependency bundles. The original web application code uses the root MIT license.
