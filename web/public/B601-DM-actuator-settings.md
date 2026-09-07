# B601-DM actuator settings reference

Checked 2026-09-06. Published source snapshot; no hardware queried.

Covers all 53 registers in the inspected MotorBridge table, all fields in Seeed’s B601-DM YAML, MIT and other motion commands, and relevant maintenance/readback operations. Firmware-specific unknowns are marked.

## Published values, not a hardware readout

No actuator has been queried. The per-joint values are defaults from a pinned Seeed configuration; actual firmware, saved registers and calibration may differ.

## MIT damping mismatch

Joints 1–3 specify kd = 8 in Seeed’s YAML. Both the inspected MotorBridge encoder and Damiao V1.4 define kd = 0–5; that encoder clips 8 to 5. The installed MotorBridge version must be checked before assuming an effective gain.

Sources: [Seeed B601-DM configuration](https://github.com/Seeed-Projects/reBotArm_control_py/blob/1bcd81b22c182ec257bf04f5746e1e3d556a5f1c/config/rebotarm_dm.yaml), [MotorBridge Damiao command encoder](https://github.com/motorbridge/motorbridge/blob/c48ebc4b2f250aa1f411a580d9d7b626e187040f/motor_vendors/damiao/src/protocol.rs), [Damiao control protocol manual V1.4](https://github.com/dmBots/damiao-document/blob/5e5a6932b8f013636415174c7433b9685ba24aa2/调试助手使用说明书（达妙驱动控制协议）V1.4.pdf).

## Mapping limits are not mechanical limits

PMAX / VMAX / TMAX describe packet scaling. Joint travel, requested speeds, thermal ratings and modeled effort limits are separate quantities. The host and motor mapping scales must agree.

Sources: [MotorBridge motor model catalog](https://github.com/motorbridge/motorbridge/blob/c48ebc4b2f250aa1f411a580d9d7b626e187040f/motor_vendors/damiao/src/motor.rs), [Seeed B601-DM URDF used by this simulator](https://github.com/Seeed-Projects/reBot-DevArm/blob/c9b893aa26c7d89019dd3d0a28ff8f6a7d47ccf9/Rebot_Arm_description/DM/urdf/ReBot_Arm_DM.urdf), [Damiao control protocol manual V1.4](https://github.com/dmBots/damiao-document/blob/5e5a6932b8f013636415174c7433b9685ba24aa2/调试助手使用说明书（达妙驱动控制协议）V1.4.pdf).

## Firmware-specific fields remain explicit

The 53-register list is complete for the inspected MotorBridge table. It does not establish every register supported by every 4310 or 4340P firmware. Extended readbacks, raw scaling, reserved fields and undocumented coefficient behavior are marked accordingly.

Sources: [MotorBridge complete Damiao register table](https://github.com/motorbridge/motorbridge/blob/c48ebc4b2f250aa1f411a580d9d7b626e187040f/motor_vendors/damiao/src/registers.rs).

## Different configuration layers

Software YAML edits affect the host when loaded. Firmware RAM writes can be lost at power-off; storing parameters persists them. MIT command gains are sent in packets. This reference is read-only and does not apply any values to the simulator or hardware.

Sources: [Seeed actuator implementation](https://github.com/Seeed-Projects/reBotArm_control_py/blob/1bcd81b22c182ec257bf04f5746e1e3d556a5f1c/reBotArm_control_py/actuator/rebotarm.py), [Damiao control protocol manual V1.4](https://github.com/dmBots/damiao-document/blob/5e5a6932b8f013636415174c7433b9685ba24aa2/调试助手使用说明书（达妙驱动控制协议）V1.4.pdf).

## Actuator assignments and encoding scales

PMAX, VMAX and TMAX below are MotorBridge catalog values, not measured device settings or continuous ratings.

| Joint | Motor model | Receive ID | Feedback ID | PMAX rad | VMAX rad/s | TMAX N·m |
| --- | --- | --- | --- | --- | --- | --- |
| joint1 | 4340P | 0x01 | 0x11 | 12.5 | 10 | 28 |
| joint2 | 4340P | 0x02 | 0x12 | 12.5 | 10 | 28 |
| joint3 | 4340P | 0x03 | 0x13 | 12.5 | 10 | 28 |
| joint4 | 4310 | 0x04 | 0x14 | 12.5 | 30 | 10 |
| joint5 | 4310 | 0x05 | 0x15 | 12.5 | 30 | 10 |
| joint6 | 4310 | 0x06 | 0x16 | 12.5 | 30 | 10 |
| gripper | 4310 | 0x07 | 0x17 | 12.5 | 30 | 10 |

Sources: [Seeed B601-DM configuration](https://github.com/Seeed-Projects/reBotArm_control_py/blob/1bcd81b22c182ec257bf04f5746e1e3d556a5f1c/config/rebotarm_dm.yaml), [MotorBridge motor model catalog](https://github.com/motorbridge/motorbridge/blob/c48ebc4b2f250aa1f411a580d9d7b626e187040f/motor_vendors/damiao/src/motor.rs).

## Published per-joint gains

MIT kp is in N·m/rad and kd in N·m·s/rad. POS_VEL gains have firmware-specific scaling; vlim is in rad/s. These are published defaults, not recommended tuning values.

| Joint | MIT kp | MIT kd | Velocity kp | Velocity ki | Position kp | Position ki | vlim |
| --- | --- | --- | --- | --- | --- | --- | --- |
| joint1 | 120.0 | 8.0 | 0.0125 | 0.004 | 150.0 | 0.5 | 5.0 |
| joint2 | 120.0 | 8.0 | 0.0125 | 0.004 | 150.0 | 0.5 | 5.0 |
| joint3 | 120.0 | 8.0 | 0.0125 | 0.004 | 150.0 | 0.5 | 5.0 |
| joint4 | 18.0 | 2.0 | 0.0008 | 0.002 | 70.0 | 1.0 | 3.0 |
| joint5 | 18.0 | 2.0 | 0.0008 | 0.002 | 60.0 | 1.0 | 3.0 |
| joint6 | 18.0 | 2.0 | 0.0008 | 0.002 | 60.0 | 1.0 | 3.0 |
| gripper | 8.0 | 1.0 | 0.0008 | 0.002 | 50.0 | 1.0 | 3.0 |

Sources: [Seeed B601-DM configuration](https://github.com/Seeed-Projects/reBotArm_control_py/blob/1bcd81b22c182ec257bf04f5746e1e3d556a5f1c/config/rebotarm_dm.yaml), [Seeed actuator implementation](https://github.com/Seeed-Projects/reBotArm_control_py/blob/1bcd81b22c182ec257bf04f5746e1e3d556a5f1c/reBotArm_control_py/actuator/rebotarm.py), [MotorBridge Damiao command encoder](https://github.com/motorbridge/motorbridge/blob/c48ebc4b2f250aa1f411a580d9d7b626e187040f/motor_vendors/damiao/src/protocol.rs).

## Control modes

Conceptual MIT control law: torque = kp × (desired position − measured position) + kd × (desired velocity − measured velocity) + feedforward torque. Firmware limiting and motor conversion also apply.

| Code | Mode | CAN command ID | Behavior |
| --- | --- | --- | --- |
| 1 | MIT | ESC_ID | Combines position, velocity, stiffness, damping and feedforward torque in one packed command. |
| 2 | Position / velocity | ESC_ID + 0x100 | Firmware moves toward a position with a commanded speed limit and its own motion ramp. |
| 3 | Velocity | ESC_ID + 0x200 | Firmware tracks a signed velocity request. |
| 4 | Force / position | ESC_ID + 0x300 | Position command with speed and torque/current limits. Listed by MotorBridge; the older V1.4 manual covers only modes 1–3. |

Sources: [MotorBridge Damiao command encoder](https://github.com/motorbridge/motorbridge/blob/c48ebc4b2f250aa1f411a580d9d7b626e187040f/motor_vendors/damiao/src/protocol.rs), [Damiao control protocol manual V1.4](https://github.com/dmBots/damiao-document/blob/5e5a6932b8f013636415174c7433b9685ba24aa2/调试助手使用说明书（达妙驱动控制协议）V1.4.pdf).

## Live command fields

| Field | Range / format | Unit | What it does |
| --- | --- | --- | --- |
| MIT p_des / pos | −PMAX … +PMAX | rad | Target output position. The SDK send_mit call requires a position array; encoding uses 16 bits. |
| MIT v_des / vel | −VMAX … +VMAX | rad/s | Desired velocity used by the damping term. Seeed defaults omitted velocity arrays to zero; encoding uses 12 bits. |
| MIT Kp / kp | 0 … 500 | N·m/rad | Position-error gain in each command. A larger value raises restoring stiffness; this is separate from firmware KP_APR. |
| MIT Kd / kd | 0 … 5 | N·m·s/rad | Velocity-error gain in each command. MotorBridge clamps outside values, including YAML kd = 8, to the encoding range. |
| MIT t_ff / tau | −TMAX … +TMAX | N·m | Feedforward torque added to the position and velocity terms. Omitted arrays default to zero in the Seeed SDK. |
| POS_VEL target_position | float32; application limits required | rad | Destination for the firmware position loop. This float format does not enforce the robot URDF travel limits by itself. |
| POS_VEL velocity_limit / vlim | float32; hardware-dependent | rad/s | Travel-speed limit sent alongside each target position. ACC and DEC determine the non-MIT ramp. |
| VEL target_velocity | float32; hardware-dependent | rad/s | Signed velocity request for the pure velocity mode. Direction follows the sign. |
| FORCE_POS target_position | float32; firmware-dependent | rad | Position target used together with speed and torque/current limiting in supported mode-4 firmware. |
| FORCE_POS velocity_limit | 0 … 100 in the inspected encoder | rad/s | Encoder clips the request to 0–100 and packs it at 0.01 resolution. This is a wire-format range, not the motor’s safe speed. |
| FORCE_POS torque_limit_ratio | 0 … 1 | fraction | Normalized torque/current ceiling in supported mode 4. MotorBridge packs ratio × 10,000; this is not a torque value in N·m. |

Sources: [MotorBridge Damiao command encoder](https://github.com/motorbridge/motorbridge/blob/c48ebc4b2f250aa1f411a580d9d7b626e187040f/motor_vendors/damiao/src/protocol.rs), [Seeed actuator implementation](https://github.com/Seeed-Projects/reBotArm_control_py/blob/1bcd81b22c182ec257bf04f5746e1e3d556a5f1c/reBotArm_control_py/actuator/rebotarm.py).

## Software configuration and gravity compensation

| Setting | Published value / API default | Unit | What it does |
| --- | --- | --- | --- |
| channel | /dev/ttyACM0 | device path | Host interface used to reach the actuators. The SDK selects the Damiao serial bridge for paths beginning /dev/tty. |
| serial baud | 921600 | bit/s | Serial bridge rate fixed in the inspected SDK controller factory. This does not set the CAN wire bit rate. |
| CAN bit rate | Installation-specific | bit/s | Seeed’s SDK README gives a 500,000 bit/s SocketCAN example; the older Damiao V1.4 manual specifies 1,000,000 bit/s. Match the actual bridge and firmware; neither is a universal B601 setting. |
| rate | 500 | Hz | Requested host control-loop frequency. It does not change the motor firmware’s internal servo frequency. |
| arm_control_mode | posvel | mode name | Default for RebotArmEndPose when no explicit mode is passed. It does not force every JointGroup into this mode; low-level groups initially track MIT. |
| groups.arm.joints | joint1 … joint6 | ordered names | Arm membership and command-array ordering; the six arm joints are controlled as one group. |
| groups.gripper.joints | gripper | ordered names | Independent gripper group. Motor 7 drives the mechanism; the two simulated finger joints are a kinematic representation. |
| joints[].name | joint1 … joint6, gripper | name | Logical key used to pair a software joint with its motor and group. |
| joints[].vendor | damiao | driver name | Chooses the actuator protocol implementation. |
| joints[].model | 4340P / 4310 | catalog name | Selects the SDK’s initial position, velocity and torque mapping scales. A wrong model can mis-scale commands and feedback. |
| joints[].motor_id | 0x01 … 0x07 | CAN ID | Software expectation for the receive ID; it does not itself prove or change the device’s ESC_ID. |
| joints[].feedback_id | 0x11 … 0x17 | CAN ID | Software expectation for the feedback arbitration ID, paired with MST_ID. |
| MIT.kp | Per-joint table | N·m/rad | Position-error stiffness sent in MIT command packets. More stiffness produces more restoring torque for the same error. |
| MIT.kd | Per-joint table | N·m·s/rad | Velocity-error damping sent in MIT packets. The inspected encoder clamps to 0–5; the first three YAML values are 8. |
| POS_VEL.vel_kp | Per-joint table | firmware gain | Written to RID 25 (KP_ASR) when the SDK configures position/velocity mode. |
| POS_VEL.vel_ki | Per-joint table | firmware gain | Written to RID 26 (KI_ASR) when configuring position/velocity mode. |
| POS_VEL.pos_kp | Per-joint table | firmware gain | Written to RID 27 (KP_APR); separate from the MIT proportional gain. |
| POS_VEL.pos_ki | Per-joint table | firmware gain | Written to RID 28 (KI_APR); actual loop semantics depend on firmware. |
| POS_VEL.vlim | 5 arm J1–3; 3 J4–7 | rad/s | Velocity limit carried with each position/velocity target. This is an output command limit, separate from VMAX and rotor-side MAX_SPD. |
| urdf_path | urdf/DM/urdf/ReBot_Arm_DM.urdf | file path | Robot geometry, joint transforms, inertial properties and modeled limits used by host kinematics. |
| end_effector_frame | end_link | frame name | Frame whose position and orientation the host controller targets. |
| gravity_compensation.kp | 1.5 in YAML; 2.0 API default | N·m/rad | Compliant MIT stiffness while hand-guiding with gravity compensation. Whether YAML or constructor defaults apply depends on the caller. |
| gravity_compensation.kd | 1.0 | N·m·s/rad | Compliant damping used with gravity compensation. |
| gravity_compensation.tau_scale | [1, 1, 1, 1, 1, 1] | per-joint factor | Scales predicted gravity torque per arm joint to compensate for model-versus-hardware differences. |
| gravity_compensation.transition_duration | 0.5 | s | Time used to blend from stiff hold gains to compliant gains at startup. |
| GravityCompensation.joint_direction | +1 by default | ±1 per joint | Transforms joint signs for the model and maps gravity torques back to hardware. Not the same as firmware RID 55. |
| GravityCompensation.hold_kp / hold_kd | Arm MIT gains unless overridden | per-joint gains | Stiff hold gains used before the compliant transition and when returning to a hold. |
| GravityCompensation.enabled_joints | All when omitted | joint names | Restricts which named motors are enabled for that controller. |
| GravityCompensation.log_every | 0 | loop count | Diagnostic print interval; zero suppresses periodic output. |
| gravity_compensation.profiles | Optional; none in DM YAML | named mappings | Loader can merge a named profile over the shared gravity settings; the inspected DM file defines no profiles. |

Sources: [Seeed B601-DM configuration](https://github.com/Seeed-Projects/reBotArm_control_py/blob/1bcd81b22c182ec257bf04f5746e1e3d556a5f1c/config/rebotarm_dm.yaml), [Seeed actuator implementation](https://github.com/Seeed-Projects/reBotArm_control_py/blob/1bcd81b22c182ec257bf04f5746e1e3d556a5f1c/reBotArm_control_py/actuator/rebotarm.py), [Seeed gravity-compensation controller](https://github.com/Seeed-Projects/reBotArm_control_py/blob/1bcd81b22c182ec257bf04f5746e1e3d556a5f1c/reBotArm_control_py/controllers/gravity_compensation.py), [Seeed B601-DM SDK setup guide](https://github.com/Seeed-Projects/reBotArm_control_py/blob/1bcd81b22c182ec257bf04f5746e1e3d556a5f1c/README.md).

## Complete firmware register catalog

RW means read/write through the documented interface; RO means read-only in MotorBridge. float32 is a 32-bit floating-point value; uint32 is an unsigned 32-bit integer. Ranges below are declared protocol ranges, not operating recommendations. Register gaps are unlisted, not free slots. Live values are unknown.

### Protection

| RID | Name | Access | Type | Declared range | Unit | What it does |
| --- | --- | --- | --- | --- | --- | --- |
| 0 | UV_Value | RW | float32 | (10.0, 3.4E38] | V | Supply threshold below which the driver protects itself from undervoltage. |
| 2 | OT_Value | RW | float32 | [80.0, 200) | °C | Motor winding temperature trip threshold. Raising it permits a hotter motor before shutdown. |
| 3 | OC_Value | RW | float32 | (0.0, 1.0) | fraction | Fraction of the peak phase-current limit. 0.5 means 50%; this is not a value in amperes. |
| 29 | OV_Value | RW | float32 | TBD | V | Upper supply-voltage threshold. The old V1.4 manual describes checking it at power-up; continuous checking is not established for every firmware. |

Sources: [MotorBridge complete Damiao register table](https://github.com/motorbridge/motorbridge/blob/c48ebc4b2f250aa1f411a580d9d7b626e187040f/motor_vendors/damiao/src/registers.rs), [Damiao control protocol manual V1.4](https://github.com/dmBots/damiao-document/blob/5e5a6932b8f013636415174c7433b9685ba24aa2/调试助手使用说明书（达妙驱动控制协议）V1.4.pdf).

### Scaling

| RID | Name | Access | Type | Declared range | Unit | What it does |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | KT_Value | RW | float32 | [0.0, 3.4E38] | N·m/A | Torque-to-current coefficient, called KT_OUT in the manual. Zero selects the firmware’s calculated coefficient in V1.4. |
| 21 | PMAX | RW | float32 | (0.0, 3.4E38] | rad | Positive magnitude used to map position to and from the packed CAN representation (−PMAX to +PMAX). It is not a joint travel limit. |
| 22 | VMAX | RW | float32 | (0.0, 3.4E38] | rad/s | Positive magnitude used to encode and decode velocity (−VMAX to +VMAX). It is not the requested operating speed. |
| 23 | TMAX | RW | float32 | (0.0, 3.4E38] | N·m | Positive magnitude used to encode and decode torque (−TMAX to +TMAX). It is not a continuous-duty torque rating. |
| 30 | GREF | RW | float32 | (0.0, 1.0] | ratio | Gearbox torque transmission efficiency used by torque conversion. It is a motor-model correction factor. |

Sources: [MotorBridge complete Damiao register table](https://github.com/motorbridge/motorbridge/blob/c48ebc4b2f250aa1f411a580d9d7b626e187040f/motor_vendors/damiao/src/registers.rs), [Damiao control protocol manual V1.4](https://github.com/dmBots/damiao-document/blob/5e5a6932b8f013636415174c7433b9685ba24aa2/调试助手使用说明书（达妙驱动控制协议）V1.4.pdf).

### Motion profile

| RID | Name | Access | Type | Declared range | Unit | What it does |
| --- | --- | --- | --- | --- | --- | --- |
| 4 | ACC | RW | float32 | (0.0, 3.4E38) | krad/s² in V1.4 | Acceleration ramp used outside MIT mode. Confirm the scaling in the installed firmware before interpreting a raw value. |
| 5 | DEC | RW | float32 | [-3.4E38, 0.0) | krad/s² in V1.4 | Deceleration ramp outside MIT mode. The register table uses a negative value; compare magnitudes with ACC. |
| 6 | MAX_SPD | RW | float32 | (0.0, 3.4E38] | rad/s, before gearbox | Rotor-side speed ceiling for velocity mode in V1.4. This differs from the command vlim and the VMAX mapping scale. |

Sources: [MotorBridge complete Damiao register table](https://github.com/motorbridge/motorbridge/blob/c48ebc4b2f250aa1f411a580d9d7b626e187040f/motor_vendors/damiao/src/registers.rs), [Damiao control protocol manual V1.4](https://github.com/dmBots/damiao-document/blob/5e5a6932b8f013636415174c7433b9685ba24aa2/调试助手使用说明书（达妙驱动控制协议）V1.4.pdf).

### Communication

| RID | Name | Access | Type | Declared range | Unit | What it does |
| --- | --- | --- | --- | --- | --- | --- |
| 7 | MST_ID | RW | uint32 | [0, 0x7FF] | CAN identifier | CAN arbitration ID used for feedback. The B601-DM software expects 0x11–0x17. |
| 8 | ESC_ID | RW | uint32 | [0, 0x7FF] | CAN identifier | Base CAN receive ID for an actuator. The B601-DM software assigns 0x01–0x07; mode-dependent command offsets are added. |
| 9 | TIMEOUT | RW | uint32 | [0, 2^32-1] | 50 µs ticks in V1.4 | Watchdog count before loss-of-command protection. Example: 20,000 ticks = 1 second. Zero behavior is not specified here. |
| 10 | CTRL_MODE | RW | uint32 | [1, 4] | mode code | Selects the command format: 1 MIT, 2 position/velocity, 3 velocity, 4 force/position in MotorBridge. Mode 4 depends on firmware support. |
| 35 | can_br | RW | uint32 | [0, 4] | enumeration 0–4 | Selects the CAN bit-rate code on supporting firmware. Code-to-bit-rate mapping is not established by these sources; do not infer it from serial baud. |

Sources: [MotorBridge complete Damiao register table](https://github.com/motorbridge/motorbridge/blob/c48ebc4b2f250aa1f411a580d9d7b626e187040f/motor_vendors/damiao/src/registers.rs), [Damiao control protocol manual V1.4](https://github.com/dmBots/damiao-document/blob/5e5a6932b8f013636415174c7433b9685ba24aa2/调试助手使用说明书（达妙驱动控制协议）V1.4.pdf).

### Motor properties

| RID | Name | Access | Type | Declared range | Unit | What it does |
| --- | --- | --- | --- | --- | --- | --- |
| 11 | Damp | RO | float32 | Not specified | N·m·s/rad | Identified viscous damping. The V1.4 manual describes it as a reference value unused by that firmware; it is not MIT kd. |
| 12 | Inertia | RO | float32 | Not specified | kg·m² | Identified rotor inertia. A motor-model property, separate from payload inertia or the robot URDF. |
| 16 | NPP | RO | uint32 | Not specified | count | Number of magnetic pole pairs used by commutation. MotorBridge exposes this as read-only. |
| 17 | Rs | RO | float32 | Not specified | mΩ in V1.4 UI | Identified phase resistance. Confirm raw-register scaling against the specific firmware; the old UI lists milliohms. |
| 18 | Ls | RO | float32 | Not specified | µH in V1.4 UI | Identified phase inductance. Confirm raw-register scaling against firmware; the old UI lists microhenries. Also spelled LS in other libraries. |
| 19 | Flux | RO | float32 | Not specified | Wb | Identified magnetic flux linkage used by the motor model. |
| 20 | Gr | RO | float32 | Not specified | ratio | Gear reduction ratio, used to relate rotor movement to output-shaft movement. Read-only in this CAN register table. |

Sources: [MotorBridge complete Damiao register table](https://github.com/motorbridge/motorbridge/blob/c48ebc4b2f250aa1f411a580d9d7b626e187040f/motor_vendors/damiao/src/registers.rs), [Damiao control protocol manual V1.4](https://github.com/dmBots/damiao-document/blob/5e5a6932b8f013636415174c7433b9685ba24aa2/调试助手使用说明书（达妙驱动控制协议）V1.4.pdf).

### Identity

| RID | Name | Access | Type | Declared range | Unit | What it does |
| --- | --- | --- | --- | --- | --- | --- |
| 13 | hw_ver | RO | uint32 | Not specified | integer | Named hardware version, but reserved in the inspected table. No portable interpretation is documented. |
| 14 | sw_ver | RO | uint32 | Not specified | integer | Firmware software-version identifier. Record it when comparing register behavior across actuators. |
| 15 | SN | RO | uint32 | Not specified | integer | Named serial number, but reserved in the inspected table. Do not assume a usable unique serial. |
| 36 | sub_ver | RO | uint32 | Not specified | integer | Firmware sub-version identifier, useful alongside sw_ver. |

Sources: [MotorBridge complete Damiao register table](https://github.com/motorbridge/motorbridge/blob/c48ebc4b2f250aa1f411a580d9d7b626e187040f/motor_vendors/damiao/src/registers.rs), [Damiao control protocol manual V1.4](https://github.com/dmBots/damiao-document/blob/5e5a6932b8f013636415174c7433b9685ba24aa2/调试助手使用说明书（达妙驱动控制协议）V1.4.pdf).

### Control loops

| RID | Name | Access | Type | Declared range | Unit | What it does |
| --- | --- | --- | --- | --- | --- | --- |
| 24 | I_BW | RW | float32 | [100.0, 10000.0] | firmware-defined bandwidth | Current-loop bandwidth setting. Faster response changes noise sensitivity and stability. The inspected table does not state a physical unit. |
| 25 | KP_ASR | RW | float32 | [0.0, 3.4E38] | firmware gain | Velocity-loop proportional gain: response to present speed error. Written from POS_VEL.vel_kp by Seeed’s SDK. |
| 26 | KI_ASR | RW | float32 | [0.0, 3.4E38] | firmware gain | Velocity-loop integral gain: accumulates speed error to reduce steady error. Written from POS_VEL.vel_ki. |
| 27 | KP_APR | RW | float32 | [0.0, 3.4E38] | firmware gain | Position-loop proportional gain in position/velocity control. Written from POS_VEL.pos_kp; separate from MIT kp. |
| 28 | KI_APR | RW | float32 | [0.0, 3.4E38] | firmware gain | Position-loop integral gain in the register table, written from POS_VEL.pos_ki. V1.4’s appendix calls this a speed integral term, so its exact firmware behavior needs confirmation. |
| 31 | Deta | RW | float32 | [1.0, 30.0] | dimensionless | Speed-loop damping factor. Smaller values may increase overshoot; larger values may slow the response. Separate from MIT kd. |
| 32 | V_BW | RW | float32 | (0.0, 500.0) | firmware-defined bandwidth | Filtering bandwidth for the velocity loop. Sets the response/noise tradeoff; the inspected sources do not establish a universal unit. |
| 33 | IQ_c1 | RW | float32 | [100.0, 10000.0] | firmware coefficient | Current-loop enhancement coefficient. The driver names it but does not document its internal equation or tuning method. |
| 34 | VL_c1 | RW | float32 | (0.0, 10000.0] | firmware coefficient | Velocity-loop enhancement coefficient. Internal implementation and tuning effects are not specified in the inspected sources. |

Sources: [MotorBridge complete Damiao register table](https://github.com/motorbridge/motorbridge/blob/c48ebc4b2f250aa1f411a580d9d7b626e187040f/motor_vendors/damiao/src/registers.rs), [Damiao control protocol manual V1.4](https://github.com/dmBots/damiao-document/blob/5e5a6932b8f013636415174c7433b9685ba24aa2/调试助手使用说明书（达妙驱动控制协议）V1.4.pdf).

### Calibration

| RID | Name | Access | Type | Declared range | Unit | What it does |
| --- | --- | --- | --- | --- | --- | --- |
| 50 | u_off | RO | float32 | Not specified | unspecified | U-phase calibration offset. Driver metadata does not define its raw unit or correction equation. |
| 51 | v_off | RO | float32 | Not specified | unspecified | V-phase calibration offset. Driver metadata does not define its raw unit or correction equation. |
| 52 | k1 | RO | float32 | Not specified | unspecified | First internal compensation coefficient. Its exact role is not described in the public register table. |
| 53 | k2 | RO | float32 | Not specified | unspecified | Second internal compensation coefficient. Its exact role is not described in the public register table. |
| 54 | m_off | RO | float32 | Not specified | unspecified angle scale | Angle offset labeled m_off. The inspected table does not identify its reference frame or scale. |
| 55 | dir | RO | float32 | Not specified | firmware encoding | Direction/calibration flag. The table declares a float but does not specify allowed values; do not assume it is a ±1 software direction setting. |
| 56 | m_off | RO | float32 | Not specified | unspecified angle scale | Motor-side angle offset, also named m_off in MotorBridge. Use RID 56 to distinguish it from RID 54; availability depends on firmware. Extended table entry; firmware-dependent. |
| 63 | Iu_off | RO | float32 | Not specified | unspecified | U-phase current-sensor calibration offset; firmware-dependent readback. Extended table entry; firmware-dependent. |
| 64 | Iv_off | RO | float32 | Not specified | unspecified | V-phase current-sensor calibration offset; firmware-dependent readback. Extended table entry; firmware-dependent. |
| 65 | Iw_off | RO | float32 | Not specified | unspecified | W-phase current-sensor calibration offset; firmware-dependent readback. Extended table entry; firmware-dependent. |

Sources: [MotorBridge complete Damiao register table](https://github.com/motorbridge/motorbridge/blob/c48ebc4b2f250aa1f411a580d9d7b626e187040f/motor_vendors/damiao/src/registers.rs), [Damiao control protocol manual V1.4](https://github.com/dmBots/damiao-document/blob/5e5a6932b8f013636415174c7433b9685ba24aa2/调试助手使用说明书（达妙驱动控制协议）V1.4.pdf).

### Diagnostics

| RID | Name | Access | Type | Declared range | Unit | What it does |
| --- | --- | --- | --- | --- | --- | --- |
| 59 | Imax | RO | float32 | Not specified | current; raw unit unspecified | Reported maximum current of the driver board. This is read-only capability data, distinct from OC_Value. Extended table entry; firmware-dependent. |
| 60 | VBus | RO | float32 | Not specified | voltage; raw unit unspecified | Supply-bus voltage readback. The register table does not define its raw scaling. Extended table entry; firmware-dependent. |
| 61 | Tpcb | RO | float32 | Not specified | temperature; raw unit unspecified | Driver-board temperature readback. Confirm scaling before treating the raw value as degrees Celsius. Extended table entry; firmware-dependent. |
| 62 | Tmtr | RO | float32 | Not specified | temperature; raw unit unspecified | Motor temperature readback. Confirm scaling; the standard feedback frame separately reports winding temperature in °C. Extended table entry; firmware-dependent. |
| 80 | p_m | RO | float32 | Not specified | position; raw scale unspecified | Motor position readback. The register table does not fully establish its coordinate convention or units. |
| 81 | xout | RO | float32 | Not specified | position; raw scale unspecified | Output-shaft position readback. Distinguish this from motor-side position; verify zero and scaling on the specific firmware. |

Sources: [MotorBridge complete Damiao register table](https://github.com/motorbridge/motorbridge/blob/c48ebc4b2f250aa1f411a580d9d7b626e187040f/motor_vendors/damiao/src/registers.rs), [Damiao control protocol manual V1.4](https://github.com/dmBots/damiao-document/blob/5e5a6932b8f013636415174c7433b9685ba24aa2/调试助手使用说明书（达妙驱动控制协议）V1.4.pdf).

## Model limits used by this simulator

URDF lower/upper bounds constrain this simulator. Its URDF effort and velocity fields are model declarations; dynamics and effort limits are not simulated. The gripper UI covers 0–90 mm nominal opening. The source finger joints allow ±0.05 m per side; that prismatic travel is not the physical gripper motor angle.

| Joint | Lower rad | Upper rad | URDF effort N·m | URDF velocity rad/s |
| --- | --- | --- | --- | --- |
| joint1 | -2.8 | 2.8 | 27.0 | 50.0 |
| joint2 | -3.14 | 0.0 | 27.0 | 50.0 |
| joint3 | -3.14 | 0.0 | 27.0 | 50.0 |
| joint4 | -1.87 | 1.57 | 7.0 | 200.0 |
| joint5 | -1.57 | 1.57 | 7.0 | 200.0 |
| joint6 | -3.14 | 3.14 | 7.0 | 200.0 |

Sources: [Seeed B601-DM URDF used by this simulator](https://github.com/Seeed-Projects/reBot-DevArm/blob/c9b893aa26c7d89019dd3d0a28ff8f6a7d47ccf9/Rebot_Arm_description/DM/urdf/ReBot_Arm_DM.urdf).

## Maintenance and persistence

| Operation | Meaning | Persistence |
| --- | --- | --- |
| Enable | Allows the drive to produce torque and accept motion commands. | Volatile state |
| Disable | Turns off active drive torque; this is not a mechanical brake. | Volatile state |
| Save position zero | Makes the present mechanical pose the encoder zero reference. This changes the relationship between commands and arm geometry. | Calibration operation |
| Clear error | Clears a latched error; the underlying fault can remain and trigger again. | Volatile state |
| Read register | Retrieves a firmware value without changing it. Use readback to establish actual device configuration. | Read-only operation |
| Write register | Changes a writable value. The driver distinguishes a RAM write from saving parameters. | Normally temporary until saved |
| Store parameters | Commits changed configuration to nonvolatile storage so it survives power cycling. The manufacturer GUI’s “write parameters” action can reset the controller. | Persistent operation |
| Request feedback | Requests or refreshes position, velocity, torque, temperature and status feedback. | Read-only operation |
| Sensor calibration / parameter identification | Manufacturer commissioning routines identify encoder alignment and motor properties. These are not ordinary gain controls. | Commissioning operation |
| Firmware version / firmware update | Version readback identifies the drive implementation; firmware replacement can change register support and behavior. | Readback / firmware operation |

Sources: [Damiao control protocol manual V1.4](https://github.com/dmBots/damiao-document/blob/5e5a6932b8f013636415174c7433b9685ba24aa2/调试助手使用说明书（达妙驱动控制协议）V1.4.pdf), [MotorBridge Damiao command encoder](https://github.com/motorbridge/motorbridge/blob/c48ebc4b2f250aa1f411a580d9d7b626e187040f/motor_vendors/damiao/src/protocol.rs).

## Feedback and status

Standard feedback reports position (rad), velocity (rad/s), torque (N·m), MOS temperature (°C), winding temperature (°C), and a status code. Position/velocity/torque decode depends on matching PMAX/VMAX/TMAX. Temperature fields are telemetry, not writable thresholds.

| Status code | Meaning |
| --- | --- |
| 0x0 | Disabled |
| 0x1 | Enabled |
| 0x8 | Overvoltage |
| 0x9 | Undervoltage |
| 0xA | Overcurrent |
| 0xB | MOS overtemperature |
| 0xC | Winding overtemperature |
| 0xD | Lost communication |
| 0xE | Overload |

Sources: [MotorBridge Damiao command encoder](https://github.com/motorbridge/motorbridge/blob/c48ebc4b2f250aa1f411a580d9d7b626e187040f/motor_vendors/damiao/src/protocol.rs), [Damiao control protocol manual V1.4](https://github.com/dmBots/damiao-document/blob/5e5a6932b8f013636415174c7433b9685ba24aa2/调试助手使用说明书（达妙驱动控制协议）V1.4.pdf).

## Source versions

- [Seeed B601-DM configuration](https://github.com/Seeed-Projects/reBotArm_control_py/blob/1bcd81b22c182ec257bf04f5746e1e3d556a5f1c/config/rebotarm_dm.yaml): Published motor assignments and software gains; not device readback.
- [Seeed actuator implementation](https://github.com/Seeed-Projects/reBotArm_control_py/blob/1bcd81b22c182ec257bf04f5746e1e3d556a5f1c/reBotArm_control_py/actuator/rebotarm.py): Parameter loading, serial rate, groups, mode selection and gain-register writes.
- [MotorBridge complete Damiao register table](https://github.com/motorbridge/motorbridge/blob/c48ebc4b2f250aa1f411a580d9d7b626e187040f/motor_vendors/damiao/src/registers.rs): 53 registers, their identifiers, access types and declared ranges.
- [MotorBridge Damiao command encoder](https://github.com/motorbridge/motorbridge/blob/c48ebc4b2f250aa1f411a580d9d7b626e187040f/motor_vendors/damiao/src/protocol.rs): MIT limits, command encoding and status codes.
- [MotorBridge motor model catalog](https://github.com/motorbridge/motorbridge/blob/c48ebc4b2f250aa1f411a580d9d7b626e187040f/motor_vendors/damiao/src/motor.rs): 4310 / 4340P encoding limits; these are not continuous torque ratings.
- [Damiao control protocol manual V1.4](https://github.com/dmBots/damiao-document/blob/5e5a6932b8f013636415174c7433b9685ba24aa2/调试助手使用说明书（达妙驱动控制协议）V1.4.pdf): Pages 10–11, 32–40: units, modes, commands and parameter meanings. Older manual; firmware differences are called out.
- [Seeed gravity-compensation controller](https://github.com/Seeed-Projects/reBotArm_control_py/blob/1bcd81b22c182ec257bf04f5746e1e3d556a5f1c/reBotArm_control_py/controllers/gravity_compensation.py): Compliant gains, torque scaling, direction and transition settings.
- [Seeed B601-DM URDF used by this simulator](https://github.com/Seeed-Projects/reBot-DevArm/blob/c9b893aa26c7d89019dd3d0a28ff8f6a7d47ccf9/Rebot_Arm_description/DM/urdf/ReBot_Arm_DM.urdf): Kinematic joint limits and model effort / velocity fields.
- [Seeed B601-DM SDK setup guide](https://github.com/Seeed-Projects/reBotArm_control_py/blob/1bcd81b22c182ec257bf04f5746e1e3d556a5f1c/README.md): Serial and SocketCAN setup examples; bus settings depend on the installed hardware.

Register metadata derived from MotorBridge, copyright (c) 2026 motorbridge, under the MIT license. The license is included below. Explanatory text is authored for this reference.

## MotorBridge license

MIT License

Copyright (c) 2026 motorbridge

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
