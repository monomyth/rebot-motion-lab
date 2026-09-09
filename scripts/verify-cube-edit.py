#!/usr/bin/env python3
"""Verify placement and size limits through the packaged MCP stdio server."""
import argparse
import json
import os
from pathlib import Path
import selectors
import subprocess
import sys
import tempfile
import time

sys.path.insert(0,str(Path(__file__).resolve().parents[1]/"examples"))
from controller_client import ReBotClient, conventional_pickup


class MCPClient(ReBotClient):
    def __init__(self,binary,env,log):
        self.process=subprocess.Popen([str(binary)],env=env,stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=log,text=True,bufsize=1)
        self.selector=selectors.DefaultSelector();self.selector.register(self.process.stdout,selectors.EVENT_READ)
        self.index=0;self.session=None;self.action_id=0
        result=self.rpc("initialize",{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"cube-edit-verifier","version":"1"}})
        assert result["serverInfo"]["name"]=="rebot-motion-lab-codex"
        self.send({"jsonrpc":"2.0","method":"notifications/initialized"})
        assert len(self.rpc("tools/list",{})["tools"])==24

    def send(self,message):
        self.process.stdin.write(json.dumps(message,allow_nan=False)+"\n");self.process.stdin.flush()

    def rpc(self,method,params):
        self.index+=1;self.send({"jsonrpc":"2.0","id":self.index,"method":method,"params":params})
        if not self.selector.select(8):raise TimeoutError("MCP response timed out")
        result=json.loads(self.process.stdout.readline())
        assert result["id"]==self.index and "error" not in result,result
        return result["result"]

    def call(self,name,**arguments):
        result=self.rpc("tools/call",{"name":name,"arguments":arguments})
        if result.get("isError"):raise RuntimeError(result["content"][0]["text"])
        return result.get("structuredContent") or json.loads(result["content"][0]["text"])

    def close(self):
        self.process.stdin.close();self.process.wait(timeout=5);self.selector.close()


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument("app",type=Path);parser.add_argument("output",type=Path)
    args=parser.parse_args();app=args.app.resolve();output=args.output.resolve();output.mkdir(parents=True,exist_ok=True)
    report={"transport":"MCP stdio","checks":[],"sizes":[]}
    with tempfile.TemporaryDirectory(prefix="rebot-cube-",dir="/tmp") as directory, (output/"native.log").open("w") as log:
        env={**os.environ,"REBOT_CONTROL_DIRECTORY":directory,"REBOT_MCP_NO_LAUNCH":"1"}
        process=subprocess.Popen([str(app/"Contents/MacOS/ReBotMotionLab"),"--mcp-integration-test"],env=env,stdout=log,stderr=log)
        client=MCPClient(app/"Contents/MacOS/ReBotMCP",env,log)
        try:
            deadline=time.monotonic()+30
            while time.monotonic()<deadline:
                try:
                    if client.call("rebot_get_state")["scene_ready"]:break
                except RuntimeError:pass
                time.sleep(0.1)
            else:raise TimeoutError("Scene did not initialize")
            client.call("rebot_configure_task",task={"cube_xy_mm":[1500,-1000],"cube_size_mm":10,"input_mode":"state","friction":0.8})
            client.wait_ready()
            initial=client.call("rebot_get_evaluation")
            assert all(abs(n-10)<0.01 for n in initial["cube_collider_size_mm"])
            assert abs(initial["cube_pose"]["position_mm"][2]-4)<0.1
            report["checks"].append("10 mm cube configured and resting outside the old reachable radius")
            client.call("rebot_set_joint",joint=1,angle_deg=15)
            deadline=time.monotonic()+8
            while time.monotonic()<deadline:
                before=client.call("rebot_get_state")
                if before["playback"]=="stopped":break
                time.sleep(0.05)
            assert abs(before["joints_deg"][0]-15)<0.01
            client.call("rebot_set_gripper",opening_mm=0)
            deadline=time.monotonic()+8
            while time.monotonic()<deadline:
                before=client.call("rebot_get_state")
                if before["playback"]=="stopped":break
                time.sleep(0.05)
            assert before["gripper_mm"]==0
            for size in [90,10,35.5]:
                result=client.call("rebot_place_cube",x_mm=-1400,y_mm=1200,size_mm=size,yaw_deg=45)
                client.wait_ready()
                observation=client.observe();evaluation=client.call("rebot_get_evaluation")
                assert observation["joints_deg"]==before["joints_deg"]
                assert observation["gripper_mm"]==before["gripper_mm"]
                assert all(abs(n-size)<0.01 for n in evaluation["cube_collider_size_mm"])
                assert abs(observation["cube_pose"]["position_mm"][2]-(-1+size/2))<0.1
                assert result["task"]["friction"]==0.8
                report["sizes"].append({"requested_mm":size,"collider_mm":evaluation["cube_collider_size_mm"],"center_z_mm":observation["cube_pose"]["position_mm"][2]})
            report["checks"].append("Resize 10–90 mm and move to arbitrary floor XY without changing arm pose, closed aperture, or task material")
            before_task=client.call("rebot_get_task");old_episode=client.observe()["episode_id"]
            for arguments in [
                {"x_mm":350,"y_mm":0,"size_mm":9.99},
                {"x_mm":350,"y_mm":0,"size_mm":90.01},
                {"x_mm":350,"y_mm":0,"size_mm":True},
                {"x_mm":1990,"y_mm":0,"size_mm":90},
                {"x_mm":1955,"y_mm":0,"size_mm":90,"yaw_deg":45},
                {"x_mm":0,"y_mm":0,"size_mm":50},
            ]:
                try:client.call("rebot_place_cube",**arguments)
                except RuntimeError:pass
                else:raise AssertionError(f"Invalid placement accepted: {arguments}")
                assert client.call("rebot_get_task")["configuration"]==before_task["configuration"]
                assert client.observe()["episode_id"]==old_episode
            report["checks"].append("Out-of-range sizes, off-floor/rotated footprints and robot overlap rejected atomically")
            client.call("rebot_reset_episode");client.wait_ready()
            task=client.call("rebot_get_task")["task"]
            assert task["cube_xy_mm"]==[-1400,1200] and task["cube_size_mm"]==35.5
            client.call("rebot_experiment_control",action="start");client.connect()
            try:client.call("rebot_place_cube",x_mm=350,y_mm=0,size_mm=50)
            except RuntimeError:pass
            else:raise AssertionError("Placement stole external control")
            time.sleep(0.2)
            assert client.call("rebot_get_evaluation")["phase"]=="running"
            client.release()
            report["checks"].append("Reset preserves cube settings; far-floor episodes run; external ownership blocks editing")
            client.call("rebot_place_cube",x_mm=350,y_mm=0,size_mm=50,yaw_deg=0);client.wait_ready()
            task=client.call("rebot_get_task")["task"]
            held,obs=conventional_pickup(client,task)
            assert held["success"] and held["hold_seconds"]>=5
            report["pickup"]={k:held[k] for k in ["clearance_mm","tilt_deg","hold_seconds"]}
            client.release()
            report["checks"].append("Existing MCP pickup and five-second level hold still pass after placement/resizing")
            report["success"]=True
        except BaseException as error:
            report["success"]=False;report["error"]=str(error)
            try:report["state"]=client.call("rebot_get_evaluation")
            except Exception:pass
            raise
        finally:
            client.close();process.terminate()
            try:process.wait(timeout=5)
            except subprocess.TimeoutExpired:process.kill();process.wait()
            (output/"report.json").write_text(json.dumps(report,indent=2))
            print(json.dumps(report,indent=2),flush=True)

if __name__=="__main__":main()
