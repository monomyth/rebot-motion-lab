#!/usr/bin/env python3
"""Drive ReBotMCP: pick the default cube, hold 5 seconds, release."""
import json
import os
import selectors
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MCP = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / ".build/out/Products/Debug/ReBotMCP"


class Client:
    def __init__(self, binary: Path):
        self.process = subprocess.Popen(
            [str(binary)],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=sys.stderr,
            text=True,
            bufsize=1,
            env={**os.environ, "REBOT_MCP_NO_LAUNCH": "1"},
        )
        self.selector = selectors.DefaultSelector()
        self.selector.register(self.process.stdout, selectors.EVENT_READ)
        self.index = 0

    def rpc(self, method, params=None):
        self.index += 1
        self.process.stdin.write(json.dumps({"jsonrpc": "2.0", "id": self.index, "method": method, "params": params or {}}) + "\n")
        self.process.stdin.flush()
        assert self.selector.select(30), f"timeout {method}"
        line = self.process.stdout.readline()
        assert line, f"MCP exited {self.process.poll()}"
        reply = json.loads(line)
        assert reply.get("id") == self.index, reply
        if "error" in reply:
            raise RuntimeError(reply["error"])
        return reply["result"]

    def initialize(self):
        info = self.rpc("initialize", {"protocolVersion": "2025-11-25", "capabilities": {}, "clientInfo": {"name": "grok-pick-demo", "version": "1"}})
        self.process.stdin.write(json.dumps({"jsonrpc": "2.0", "method": "notifications/initialized"}) + "\n")
        self.process.stdin.flush()
        return info

    def call(self, name, arguments=None):
        result = self.rpc("tools/call", {"name": name, "arguments": arguments or {}})
        if result.get("isError"):
            raise RuntimeError(result["content"][0]["text"])
        return result.get("structuredContent") or json.loads(result["content"][0]["text"])

    def wait_stopped(self, timeout=20):
        deadline = time.monotonic() + timeout
        state = None
        while time.monotonic() < deadline:
            state = self.call("rebot_get_state")
            if state["playback"] == "stopped" and not state["manual_motion"]:
                return state
            time.sleep(0.1)
        raise TimeoutError(f"still moving: {state and state.get('status')}")

    def close(self):
        try:
            self.process.stdin.close()
        except BrokenPipeError:
            pass
        self.process.wait(timeout=5)


def cube(state):
    return state["objects"]["cube"]


def main():
    log = []
    client = Client(MCP)
    try:
        info = client.initialize()
        log.append({"step": "initialize", "server": info.get("serverInfo")})
        state = None
        for _ in range(80):
            try:
                state = client.call("rebot_get_state")
                if state.get("scene_ready"):
                    break
            except RuntimeError:
                time.sleep(0.25)
                state = None
        if not state or not state.get("scene_ready"):
            raise SystemExit("simulator is not ready — start ReBotMotionLab from the grok clone first")
        log.append({"step": "ready", "control_mode": state.get("control_mode"), "app_version": state.get("app_version")})

        client.call("rebot_playback", {"action": "reset"})
        state = client.wait_stopped()
        client.call("rebot_set_view", {"camera": "Front", "grid": True, "tool_axes": True})
        client.call("rebot_set_cube", {"present": True, "x_mm": 280, "y_mm": 0, "z_mm": 20, "size_mm": 40})
        spawn = cube(client.call("rebot_get_state"))
        log.append({"step": "spawn", "cube": spawn})

        client.call("rebot_apply_preset", {"name": "Ready"})
        client.wait_stopped()
        client.call("rebot_set_gripper", {"opening_mm": 60})
        client.wait_stopped()

        cx, cy = spawn["center_mm"]["x"], spawn["center_mm"]["y"]
        # Position-only IK: keep_level solutions currently drive the wrist into the floor.
        # Grasp AABB needs TCP within ~25 mm of the cube center (z≈19 mm). Open fingers
        # hit the plane below ~40 mm, so 40 mm is the reachable grasp height.
        client.call("rebot_move_to_position", {"x_mm": cx, "y_mm": cy, "z_mm": 80})
        client.wait_stopped()
        client.call("rebot_move_to_position", {"x_mm": cx, "y_mm": cy, "z_mm": 40})
        approach = client.wait_stopped()
        log.append({"step": "approach", "tcp_mm": approach["tcp_mm"], "attached": cube(approach)["attached"], "min_mm": approach["floor"]["minimum_robot_height_mm"]})

        client.call("rebot_set_gripper", {"opening_mm": 20})
        grabbed = client.wait_stopped()
        log.append({"step": "close", "attached": cube(grabbed)["attached"], "gripper_mm": grabbed["gripper_mm"], "tcp_mm": grabbed["tcp_mm"]})
        if not cube(grabbed)["attached"]:
            raise SystemExit(f"cube did not attach: tcp={grabbed['tcp_mm']} cube={cube(grabbed)}")

        client.call("rebot_move_to_position", {"x_mm": cx, "y_mm": cy, "z_mm": 150})
        held = client.wait_stopped()
        log.append({"step": "lift", "attached": cube(held)["attached"], "tcp_mm": held["tcp_mm"], "tcp_level": held.get("tcp_level")})
        time.sleep(5)
        still = client.call("rebot_get_state")
        log.append({"step": "hold_5s", "attached": cube(still)["attached"], "tcp_mm": still["tcp_mm"]})

        client.call("rebot_set_gripper", {"opening_mm": 60})
        dropped = client.wait_stopped()
        log.append({"step": "release", "attached": cube(dropped)["attached"], "cube": cube(dropped), "tcp_mm": dropped["tcp_mm"]})
        landed = dropped
        deadline = time.monotonic() + 3
        while time.monotonic() < deadline:
            landed = client.call("rebot_get_state")
            c = cube(landed)
            if not c["attached"] and not c.get("falling") and c["center_mm"]["z"] < 25:
                break
            time.sleep(0.05)
        log.append({"step": "landed", "cube": cube(landed), "tcp_mm": landed["tcp_mm"]})
        print(json.dumps({"ok": True, "log": log}, indent=2))
        if cube(dropped)["attached"]:
            raise SystemExit("cube still attached after release")
        if not cube(held)["attached"] or not cube(still)["attached"]:
            raise SystemExit("cube was not held for 5 seconds")
        ground = cube(landed)["center_mm"]["z"]
        if cube(landed)["attached"] or cube(landed).get("falling") or ground > 25:
            raise SystemExit(f"cube did not land on the plane: {cube(landed)}")
    finally:
        client.close()


if __name__ == "__main__":
    main()
