#!/usr/bin/env python3
"""Launch an isolated native app and exercise actual cube physics through its public IPC."""
import argparse
import base64
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "examples"))
from controller_client import ReBotClient, conventional_pickup

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument("binary",type=Path)
    parser.add_argument("output",type=Path)
    parser.add_argument("--keep-open",action="store_true")
    parser.add_argument("--cube-x",type=float,default=350)
    parser.add_argument("--cube-y",type=float,default=0)
    parser.add_argument("--cube-yaw",type=float,default=0)
    parser.add_argument("--inspection-seconds",type=float,default=0)
    parser.add_argument("--skip-contracts",action="store_true")
    args=parser.parse_args()
    output=args.output.resolve(); output.mkdir(parents=True,exist_ok=True)
    control=Path(tempfile.mkdtemp(prefix="rebot-fly-",dir="/tmp"))
    env={**os.environ,"REBOT_CONTROL_DIRECTORY":str(control),"REBOT_MCP_NO_LAUNCH":"1"}
    log=(output/"native.log").open("w")
    process=subprocess.Popen([str(args.binary.resolve()),"--mcp-integration-test"],env=env,stdout=log,stderr=log)
    report={"checks":[],"pid":process.pid,"control_directory":str(control)}
    try:
        client=ReBotClient(control)
        deadline=time.monotonic()+30
        while time.monotonic()<deadline:
            try:
                if client.call("rebot_get_state")["scene_ready"]: break
            except (OSError,RuntimeError): pass
            time.sleep(0.2)
        else: raise TimeoutError("Native app did not initialize")
        if not args.skip_contracts:
            client.call("rebot_configure_task",task={})
            client.call("rebot_playback",action="stop")
            time.sleep(0.2)
            assert client.call("rebot_get_task")["state"]["phase"]=="disabled"
            report["checks"].append("Asynchronous setup can be cancelled without a partial scene")
        result=client.call("rebot_configure_task",task={"input_mode":"state","cube_xy_mm":[args.cube_x,args.cube_y],"cube_yaw_deg":args.cube_yaw})
        task=result["task"]; client.wait_ready()
        report["checks"].append("Cube configuration and gravity settling")
        if not args.skip_contracts:
            client.call("rebot_experiment_control",action="start")
            obs=client.connect(model_id="contract-verification")
            obs=client.action(obs,obs["joints_deg"],obs["gripper_mm"])
            def rejected(name, **arguments):
                try:
                    client.call(name, **arguments)
                except RuntimeError:
                    return
                raise AssertionError(f"Expected rejection from {name}")
            rejected("rebot_set_joint",joint=1,angle_deg=10)
            rejected("rebot_controller_action",token=client.session["token"],episode_id=obs["episode_id"],
                     action_id=0,observed_frame_id=obs["frame_id"],joints_deg=obs["joints_deg"],gripper_mm=obs["gripper_mm"])
            rejected("rebot_controller_action",token=client.session["token"],episode_id=obs["episode_id"],
                     action_id=1,observed_frame_id=obs["frame_id"]+100000,joints_deg=obs["joints_deg"],gripper_mm=obs["gripper_mm"])
            obs=client.action(obs,obs["joints_deg"],obs["gripper_mm"])
            assert obs["last_action_id"]==1
            old_session=client.session.copy()
            client.call("rebot_experiment_control",action="pause")
            before=client.observe(); time.sleep(0.3); after=client.observe()
            assert before["simulation_time"]==after["simulation_time"]
            assert before["task_time"]==after["task_time"]
            assert before["cube_pose"]==after["cube_pose"]
            client.call("rebot_experiment_control",action="resume")
            client.call("rebot_reset_episode"); client.wait_ready()
            client.call("rebot_experiment_control",action="start")
            current=client.observe()
            rejected("rebot_controller_action",token=old_session["token"],episode_id=old_session["episode_id"],
                     action_id=2,observed_frame_id=current["frame_id"],joints_deg=current["joints_deg"],gripper_mm=current["gripper_mm"])
            client.call("rebot_reset_episode"); client.wait_ready()
            report["checks"].append("Exclusive ownership, duplicate/future/stale action rejection, and paused physics clock")
        for name,obs in [("initial",client.observe(images=True))]:
            (output/f'{name}-observation.json').write_text(json.dumps(obs))
            for camera in obs["images"]:
                (output/f'{name}-{camera["name"]}.jpg').write_bytes(base64.b64decode(camera["jpeg_base64"]))
        report["checks"].append("Synchronized front/top RGB observation")
        recording=client.call("rebot_recording",action="start")
        samples=[]
        state,obs=conventional_pickup(client,task,report=samples.append)
        report["pickup"]=state
        report["checks"].append("External conventional controller: contact grasp, lift >=100 mm, tilt <=5 degrees, five-second hold")
        image_obs=client.observe(images=True)
        for camera in image_obs["images"]:
            (output/f'held-{camera["name"]}.jpg').write_bytes(base64.b64decode(camera["jpeg_base64"]))
        inspection_end=time.monotonic()+min(60,max(0,args.inspection_seconds))
        while time.monotonic()<inspection_end:
            obs=client.action(client.observe(),obs["joints_deg"],0)
            time.sleep(0.1)
        obs=client.observe()
        target=obs["joints_deg"]
        deadline=time.monotonic()+6
        while time.monotonic()<deadline:
            obs=client.action(obs,target,90)
            state=client.call("rebot_get_evaluation")
            if state["clearance_mm"]<2 and not state["held"]: break
            time.sleep(0.1)
        else: raise AssertionError("Cube did not fall after release")
        report["release"]=state; report["checks"].append("Opening fingers releases cube under gravity")
        # Keep last target active but stop sending actions; only the arm command lease should expire.
        time.sleep(2.2)
        assert client.observe()["owner"]=="manual"
        report["checks"].append("Controller timeout releases ownership")
        result=client.call("rebot_recording",action="stop")
        assert result["complete"],result
        shutil.copytree(recording["directory"],output/"recording",dirs_exist_ok=True)
        events=[json.loads(line) for line in (output/"recording/events.jsonl").open()]
        assert sum(event["type"]=="observation" for event in events)>=5
        assert any(event["type"]=="controller_connected" and event["provenance"]=="conventional" for event in events)
        report["checks"].append("Demonstration recording includes camera observations, actions, outcomes, and controller provenance")
        deadline=time.monotonic()+4
        while client.call("rebot_get_evaluation")["capture_in_progress"] and time.monotonic()<deadline:
            time.sleep(0.05)
        client.call("rebot_reset_episode"); client.wait_ready()
        state=client.call("rebot_get_evaluation")
        assert not state["success"] and state["hold_seconds"]==0 and not state["dropped"]
        report["checks"].append("Reset clears success, velocities, contacts and controller")
        client.call("rebot_experiment_control",action="disable")
        client.call("rebot_configure_task",task={"input_mode":"vision"}); client.wait_ready()
        assert "cube_pose" not in client.observe()
        report["checks"].append("Vision policy observation excludes exact cube pose")
        report["success"]=True
    except BaseException as error:
        report["success"]=False; report["error"]=str(error)
        try: report["failure_state"]=client.call("rebot_get_evaluation")
        except Exception: pass
        raise
    finally:
        try:
            result=client.call("rebot_recording",action="stop")
            if result.get("directory"):
                shutil.copytree(result["directory"],output/"recording",dirs_exist_ok=True)
        except Exception:
            pass
        (output/"report.json").write_text(json.dumps(report,indent=2))
        print(json.dumps(report,indent=2),flush=True)
        if not args.keep_open:
            process.terminate()
            try: process.wait(timeout=5)
            except subprocess.TimeoutExpired: process.kill(); process.wait()
            shutil.rmtree(control)
        log.close()

if __name__=="__main__": main()
