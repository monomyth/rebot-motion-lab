import Foundation

extension ControlCatalog {
    static var experimentTools: [[String:Any]] {
        func number(_ min:Double = -2000,_ max:Double = 2000) -> [String:Any] { ["type":"number","minimum":min,"maximum":max] }
        func string(_ values:[String]? = nil) -> [String:Any] { var s:[String:Any] = ["type":"string","minLength":1,"maxLength":200]; if let values { s["enum"]=values }; return s }
        func array(_ n:Int) -> [String:Any] { ["type":"array","items":number(),"minItems":n,"maxItems":n] }
        func object(_ properties:[String:Any],_ required:[String] = []) -> [String:Any] { ["type":"object","properties":properties,"required":required,"additionalProperties":false] }
        func tool(_ name:String,_ description:String,_ props:[String:Any] = [:],_ required:[String] = [],readOnly:Bool=false) -> [String:Any] {
            ["name":name,"description":description,"inputSchema":object(props,required),"annotations":["readOnlyHint":readOnly,"destructiveHint":false,"openWorldHint":false]]
        }
        let pose=object(["position_mm":array(3),"quaternion_xyzw":array(4)],["position_mm","quaternion_xyzw"])
        let task=object(["version":["type":"integer","enum":[1]],"cube_size_mm":number(10,90),"cube_xy_mm":array(2),"cube_yaw_deg":number(-180,180),
            "mass_grams":number(10,250),"friction":number(0.1,2),"lift_clearance_mm":number(20,250),"tilt_tolerance_deg":number(1,30),
            "hold_seconds":number(1,60),"timeout_seconds":number(6,600),"stable_linear_mm_s":number(1,100),"stable_angular_deg_s":number(1,90),
            "initial_joints_deg":array(6),"initial_gripper_mm":number(0,90),"input_mode":string(["vision","state"]),"placement_jitter_mm":number(0,20),"seed":["type":"integer","minimum":0,"maximum":9007199254740991]])
        let poseArgs:[String:Any] = ["pose":pose,"frame":string(["tool","grasp"]),"gripper_mm":number(0,90)]
        return [
            tool("rebot_configure_task","Configure a native contact-physics cube experiment. Partial task fields override defaults. Requires stopped motion, no controller, and macOS 15+.",["task":task],["task"]),
            tool("rebot_place_cube","Place or resize the existing cube on the floor without moving the robot. Positions need not be reachable by the arm. The full cube must fit on the floor. Begins a new episode and clears placement jitter; stop motion, recording and external control first.",
                 ["x_mm":number(),"y_mm":number(),"size_mm":number(10,90),"yaw_deg":number(-180,180)], ["x_mm","y_mm"]),
            tool("rebot_get_task","Read task configuration, backend capabilities, and evaluator status. Contains privileged setup/evaluator data; do not feed into a vision-only policy.",readOnly:true),
            tool("rebot_reset_episode","Atomically reset robot, cube, physics, pending actions, and scoring. Optional seed controls configured XY jitter. Invalidates the controller token; wait until phase is ready.",["seed":["type":"integer","minimum":0,"maximum":9007199254740991]]),
            tool("rebot_get_observation","Read synchronized policy observations. Optional bounded JPEG front/top images. Exact cube state is omitted in vision mode.",["images":["type":"boolean"]],readOnly:true),
            tool("rebot_get_evaluation","Read privileged cube pose, contacts, clearance, tilt, and success. Separate from policy input.",readOnly:true),
            tool("rebot_experiment_control","Control experiment lifecycle. Pause freezes experiment time/physics; stop or takeover stops arm commands while physics continues.",["action":string(["start","pause","resume","stop","takeover","disable"])],["action"]),
            tool("rebot_controller_connect","Acquire exclusive episode-scoped motion control. Submit actions within two seconds to retain ownership.",["provenance":string(["conventional","teacher_assisted","malecns"]),"model_id":string()],["provenance","model_id"]),
            tool("rebot_controller_action","Submit a rate-limited joint/gripper target with episode/frame correlation. Acceptance is not arrival. New action IDs must increase.",
                 ["token":string(),"episode_id":string(),"action_id":["type":"integer","minimum":0,"maximum":9007199254740991],"observed_frame_id":["type":"integer","minimum":0,"maximum":9007199254740991],"joints_deg":array(6),"gripper_mm":number(0,90)],
                 ["token","episode_id","action_id","observed_frame_id","joints_deg","gripper_mm"]),
            tool("rebot_solve_pose","Solve position and quaternion orientation without moving. Frame defaults to grasp center 20 mm behind the tool tip.",poseArgs,["pose"],readOnly:true),
            tool("rebot_move_to_pose","Smoothly move to a full Cartesian pose; requires stopped motion and no external owner.",poseArgs,["pose"]),
            tool("rebot_recording","Start or finish a bounded local episode recording. Returns its private local directory.",["action":string(["start","stop"])],["action"])
        ]
    }
}
