#!/usr/bin/env python3
"""Exercise the packaged stdio server against an isolated native simulator instance."""
import argparse
import base64
import json
import os
from pathlib import Path
import selectors
import socket
import subprocess
import tempfile
import time

parser = argparse.ArgumentParser()
parser.add_argument("app", type=Path)
parser.add_argument("output", type=Path)
options = parser.parse_args()
app = options.app.resolve()
options.output.mkdir(parents=True, exist_ok=True)
checks = []

class Client:
    def __init__(self, env, log):
        self.process = subprocess.Popen([str(app / "Contents/MacOS/ReBotMCP")], stdin=subprocess.PIPE,
                                        stdout=subprocess.PIPE, stderr=log, env=env, text=True, bufsize=1)
        self.selector = selectors.DefaultSelector()
        self.selector.register(self.process.stdout, selectors.EVENT_READ)
        self.index = 0

    def send(self, message):
        self.process.stdin.write(json.dumps(message, separators=(",", ":")) + "\n")
        self.process.stdin.flush()

    def rpc(self, method, params=None):
        self.index += 1
        self.send({"jsonrpc": "2.0", "id": self.index, "method": method, "params": params or {}})
        assert self.selector.select(20), f"Timeout in {method}"
        line = self.process.stdout.readline()
        assert line, f"Server exited: {self.process.poll()}"
        reply = json.loads(line)
        assert reply["id"] == self.index and reply["jsonrpc"] == "2.0", reply
        return reply

    def initialize(self):
        result = self.rpc("initialize", {"protocolVersion": "2025-11-25", "capabilities": {},
                     "clientInfo": {"name": "rebot-integration-test", "version": "1"}})["result"]
        assert result["protocolVersion"] == "2025-11-25"
        self.send({"jsonrpc": "2.0", "method": "notifications/initialized"})

    def call(self, name, arguments=None, fails=False):
        result = self.rpc("tools/call", {"name": name, "arguments": arguments or {}})["result"]
        assert bool(result.get("isError")) == fails, result
        if fails:
            return result["content"][0]["text"]
        parsed = json.loads(result["content"][0]["text"])
        assert parsed == result["structuredContent"]
        return parsed

    def state(self):
        return self.call("rebot_get_state")

    def wait_stopped(self, timeout=12):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            state = self.state()
            if state["playback"] == "stopped" and not state["manual_motion"]: return state
            time.sleep(0.08)
        raise AssertionError("Motion did not complete")

    def close(self):
        self.process.stdin.close()
        self.process.wait(timeout=5)
        assert self.process.returncode == 0
        self.selector.close()

with tempfile.TemporaryDirectory(prefix="rebot-mcp-", dir="/tmp") as directory:
    env = {**os.environ, "REBOT_CONTROL_DIRECTORY": directory, "REBOT_MCP_NO_LAUNCH": "1"}
    with (options.output / "native.log").open("w") as native_log, (options.output / "server.log").open("w") as server_log:
        client = Client(env, server_log)
        simulator = None
        try:
            client.initialize()
            assert len(client.rpc("tools/list")["result"]["tools"]) == 18
            assert len(client.rpc("resources/list")["result"]["resources"]) == 2
            client.call("rebot_get_state", fails=True)
            checks.append("MCP handshake, tool/resource discovery, and unavailable-app error")
            simulator = subprocess.Popen([str(app / "Contents/MacOS/ReBotMotionLab"), "--mcp-integration-test"],
                                         env=env, stdout=native_log, stderr=native_log)
            deadline = time.monotonic() + 30
            while time.monotonic() < deadline:
                if (Path(directory) / "control.sock").exists():
                    state = client.state()
                    if state["scene_ready"]: break
                time.sleep(0.25)
            else: raise AssertionError("Native scene never became ready")
            assert state["process_id"] == simulator.pid and state["joints_deg"] == [0]*6 and state["gripper_mm"] == 0
            assert not state["hardware_connected"]
            assert (Path(directory) / "control.sock").stat().st_mode & 0o777 == 0o600
            checks.append("Live native instance identity, folded startup, and private socket permissions")
            result = client.call("rebot_set_joint", {"joint": 1, "angle_deg": 25})
            assert result["accepted"] and result["state"]["playback"] == "playing"
            client.call("rebot_set_gripper", {"opening_mm": 20}, fails=True)
            assert abs(client.wait_stopped()["joints_deg"][0] - 25) < 0.001
            client.call("rebot_set_gripper", {"opening_mm": 35})
            assert client.wait_stopped()["gripper_mm"] == 35
            checks.append("Smooth joint and gripper motion reaches requested endpoints; overlapping motion rejected")
            before = client.state()
            for name, args in [("rebot_set_joint", {"joint": 1, "angle_deg": 999}),
                               ("rebot_set_joint", {"joint": 7, "angle_deg": 0}),
                               ("rebot_set_joint", {"joint": True, "angle_deg": 0}),
                               ("rebot_set_gripper", {"opening_mm": -1}),
                               ("rebot_move_joints", {"joints_deg": [0,0,0,0,0]}),
                               ("rebot_move_to_position", {"x_mm": 5000, "y_mm": 5000, "z_mm": 5000})]:
                client.call(name, args, fails=True)
            assert client.state()["joints_deg"] == before["joints_deg"]
            assert client.state()["command_revision"] == before["command_revision"]
            checks.append("Invalid types, bounds, array lengths, and unreachable IK preserve pose and revision")
            client.call("rebot_apply_preset", {"name": "Ready"})
            ready = client.wait_stopped()
            assert ready["joints_deg"] == [0,-95,-95,10,0,0]
            tcp = ready["tcp_mm"]
            client.call("rebot_move_to_position", {"x_mm": tcp["x"]-10, "y_mm": tcp["y"]+10, "z_mm": tcp["z"]+10})
            moved = client.wait_stopped()["tcp_mm"]
            assert sum((moved[k] - (tcp[k] + (-10 if k == "x" else 10)))**2 for k in tcp)**0.5 < 2
            client.call("rebot_move_joints", {"joints_deg": [0,-95,-95,10,0,0], "gripper_mm": 20})
            assert client.wait_stopped()["gripper_mm"] == 20
            checks.append("Preset, six-joint pose, and Cartesian IK commands complete in the native scene")
            client.call("rebot_clear_sequence")
            client.call("rebot_add_waypoint", {"name": "Current"})
            assert client.state()["waypoints"][0]["name"] == "Current"
            sequence = [{"name": "Left", "joints_deg": [-20,-95,-95,10,0,0], "gripper_mm": 20},
                        {"name": "Right", "joints_deg": [20,-95,-95,10,0,0], "gripper_mm": 0}]
            client.call("rebot_set_sequence", {"poses": sequence})
            snapshot = client.state()["waypoints"]
            client.call("rebot_set_sequence", {"poses": sequence + [{"name":"Bad", "joints_deg":[999]*6, "gripper_mm": 0}]}, fails=True)
            assert client.state()["waypoints"] == snapshot
            client.call("rebot_set_speed", {"percent": 100})
            client.call("rebot_playback", {"action": "play"})
            time.sleep(0.15)
            client.call("rebot_playback", {"action": "pause"})
            paused = client.state()["joints_deg"]
            time.sleep(0.25)
            assert client.state()["joints_deg"] == paused
            client.call("rebot_playback", {"action": "resume"})
            assert client.wait_stopped()["joints_deg"][0] == 20
            checks.append("Waypoint add/clear/atomic replace, speed, sequence play/pause/resume/completion")
            client.call("rebot_playback", {"action": "play"})
            client.call("rebot_playback", {"action": "stop"})
            stopped = client.state()["joints_deg"]
            time.sleep(0.2)
            assert client.state()["joints_deg"] == stopped
            client.call("rebot_set_view", {"camera": "Front", "grid": False, "trace": True, "tool_axes": False, "clear_trace": True})
            assert client.state()["view"] == {"camera": "Front", "grid": False, "trace": True, "tool_axes": False}
            reference = client.rpc("resources/read", {"uri": "rebot://actuators"})["result"]["contents"][0]["text"]
            assert "PMAX" in reference and "Damiao" in reference
            assert "error" in client.rpc("resources/read", {"uri": "file:///etc/passwd"})
            resource_state = client.rpc("resources/read", {"uri": "rebot://state"})["result"]["contents"][0]["text"]
            assert json.loads(resource_state)["process_id"] == simulator.pid
            checks.append("Stop holds pose, camera/overlay controls, and scoped state/reference resources")
            client.call("rebot_move_joints", {"joints_deg": [0,-95,-95,10,0,90], "gripper_mm": 90})
            before_floor = client.wait_stopped()
            rejected = client.call("rebot_set_joint", {"joint": 2, "angle_deg": -179}, fails=True)
            assert "base plane" in rejected
            after_floor = client.state()
            assert after_floor["joints_deg"] == before_floor["joints_deg"]
            assert after_floor["command_revision"] == before_floor["command_revision"]
            assert after_floor["floor"]["enabled"] and after_floor["floor"]["height_mm"] == -1
            assert after_floor["floor"]["minimum_robot_height_mm"] >= -1
            checks.append("MCP rejects gripper-tip floor penetration and exposes the solid-plane state")
            # A malformed private-IPC request must not crash the app or block subsequent clients.
            with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as raw:
                raw.settimeout(6); raw.connect(str(Path(directory)/"control.sock")); raw.sendall(b"not-json\n")
                assert json.loads(raw.recv(8192))["ok"] is False
            client.call("rebot_playback", {"action": "reset"})
            assert client.state()["joints_deg"] == [0]*6 and client.state()["gripper_mm"] == 0
            cube = client.state()["objects"]["cube"]
            assert cube["present"] and not cube["attached"]
            assert abs(cube["center_mm"]["x"] - 280) < 1
            limits = client.state()["cube_size_limits_mm"]
            assert abs(limits[0] - 10) < 1e-6 and abs(limits[1] - 90) < 1e-6
            client.call("rebot_set_cube", {"size_mm": 5}, fails=True)
            client.call("rebot_set_cube", {"size_mm": 100}, fails=True)
            assert abs(client.state()["objects"]["cube"]["center_mm"]["x"] - 280) < 1
            client.call("rebot_set_cube", {"size_mm": 10})
            assert abs(client.state()["objects"]["cube"]["size_mm"] - 10) < 0.1
            client.call("rebot_set_cube", {"size_mm": 90})
            assert abs(client.state()["objects"]["cube"]["size_mm"] - 90) < 0.1
            client.call("rebot_set_cube", {"x_mm": 300, "y_mm": 40, "z_mm": 400, "size_mm": 40, "yaw_deg": 15})
            placed = client.state()["objects"]["cube"]
            assert abs(placed["center_mm"]["x"] - 300) < 0.1
            assert abs(placed["center_mm"]["y"] - 40) < 0.1
            assert abs(placed["size_mm"] - 40) < 0.1
            assert abs(placed["center_mm"]["z"] - 19) < 0.5
            assert not placed["attached"]
            client.call("rebot_playback", {"action": "reset"})
            restored = client.state()["objects"]["cube"]
            assert abs(restored["center_mm"]["x"] - 300) < 0.1
            assert abs(restored["center_mm"]["y"] - 40) < 0.1
            assert abs(restored["size_mm"] - 40) < 0.1
            assert not restored["attached"]
            client.call("rebot_set_cube", {"x_mm": 280, "y_mm": 0, "size_mm": 40, "yaw_deg": 0})
            checks.append("Cube XY placement, 10–90 mm size, ignored Z, reset-to-spawn")
            client.call("rebot_apply_preset", {"name": "Ready"})
            client.wait_stopped()
            client.call("rebot_set_control_mode", {"mode": "servo"})
            assert client.state()["control_mode"] == "servo"
            client.call("rebot_move_joints", {"joints_deg": [0,-95,-95,10,0,0]}, fails=True)
            started = time.monotonic()
            servo = client.call("rebot_servo_joints", {"joints_deg": [10,-95,-95,10,0,0], "gripper_mm": 40})
            elapsed = (time.monotonic() - started) * 1000
            assert servo["accepted"] and abs(client.state()["joints_deg"][0] - 10) < 0.001
            client.call("rebot_set_control_mode", {"mode": "scripted"})
            assert client.state()["control_mode"] == "scripted"
            checks.append(f"Servo mode rejects scripted moves and applies immediate joints ({elapsed:.1f} ms)")
            pose = client.call("rebot_move_to_pose", {"x_mm": 280, "y_mm": 0, "z_mm": 200, "keep_level": True})
            assert pose["accepted"]
            leveled = client.wait_stopped()
            assert leveled["tcp_level"] is True
            assert abs(leveled["tcp_mm"]["x"] - 280) < 2
            kept = client.state()["view"]["camera"]
            for name in ("Front", "Gripper"):
                capture = client.call("rebot_capture_view", {"camera": name, "width": 320, "height": 240, "apply": False})
                assert capture["width"] == 320
                jpeg = base64.b64decode(capture["jpeg_base64"])
                assert jpeg[:2] == b"\xff\xd8"
                (options.output / f"capture-{name.lower()}.jpg").write_bytes(jpeg)
            assert client.state()["view"]["camera"] == kept
            checks.append("Level IK, Front+Gripper capture, camera apply=false")
            client.call("rebot_playback", {"action": "reset"})
            assert client.state()["joints_deg"] == [0]*6 and client.state()["gripper_mm"] == 0
            checks.append("Malformed IPC recovery and reset to folded startup")
            (options.output / "mcp-result.json").write_text(json.dumps({"passed": checks, "final_state": client.state()}, indent=2))
            print(f"PASS: {len(checks)} MCP integration groups")
        except Exception as error:
            (options.output / "mcp-error.txt").write_text(str(error))
            raise
        finally:
            client.close()
            if simulator is not None:
                simulator.terminate()
                simulator.wait(timeout=10)
