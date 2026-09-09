import Testing
import Foundation
import RobotControl

struct ExperimentCatalogTests {
    @Test func malformedExperimentCommandsDoNotReachBackend() throws {
        let bad: [(String,[String:Any])] = [
            ("rebot_configure_task",["task":["cube_size_mm":100]]),
            ("rebot_configure_task",["task":["cube_size_mm":9.99]]),
            ("rebot_place_cube",["x_mm":350,"y_mm":0,"size_mm":90.01]),
            ("rebot_place_cube",["x_mm":350,"y_mm":0,"size_mm":9.99]),
            ("rebot_place_cube",["x_mm":true,"y_mm":0]),
            ("rebot_configure_task",["task":["input_mode":"secret"]]),
            ("rebot_configure_task",["task":["unknown":1]]),
            ("rebot_get_observation",["images":1]),
            ("rebot_reset_episode",["seed":-1]),
            ("rebot_controller_connect",["provenance":"manual","model_id":"x"]),
            ("rebot_controller_action",["token":"x","episode_id":"one","action_id":true,"observed_frame_id":0,"joints_deg":[0,0,0,0,0,0],"gripper_mm":30]),
            ("rebot_controller_action",["token":"x","episode_id":"one","action_id":1e30,"observed_frame_id":0,"joints_deg":[0,0,0,0,0,0],"gripper_mm":30]),
            ("rebot_move_to_pose",["pose":["position_mm":[0,0],"quaternion_xyzw":[0,0,0,1]]])
        ]
        for (name,args) in bad { #expect(throws:ControlError.self) { try ControlCatalog.validate(args,for:name) } }
        try ControlCatalog.validate(["task":["cube_xy_mm":[350,20],"placement_jitter_mm":10,"seed":42]],for:"rebot_configure_task")
        for size in [10.0,90] {
            try ControlCatalog.validate(["x_mm":1500,"y_mm":-1500,"size_mm":size],for:"rebot_place_cube")
            try ControlCatalog.validate(["task":["cube_xy_mm":[1500,-1500],"cube_size_mm":size]],for:"rebot_configure_task")
        }
        try ControlCatalog.validate(["pose":["position_mm":[350,0,140],"quaternion_xyzw":[0,0.70710678118,0,0.70710678118]],"frame":"grasp"],for:"rebot_solve_pose")
    }
    @Test func legacyAndExperimentNamesStayAvailable() {
        let names=Set(ControlCatalog.tools.compactMap { $0["name"] as? String })
        #expect(names.isSuperset(of:["rebot_move_joints","rebot_move_to_position","rebot_set_view","rebot_get_state","rebot_get_observation","rebot_controller_action","rebot_recording"]))
        #expect(names.count==ControlCatalog.tools.count)
    }
}
