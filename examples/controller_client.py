"""Dependency-free local controller client. Does not launch or connect to hardware."""
import ctypes
import json
import os
from pathlib import Path
import socket
import stat
import time


class ReBotClient:
    def __init__(self, directory):
        self.directory = Path(directory)
        info = self.directory.lstat()
        if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid() or info.st_mode & 0o077:
            raise ValueError("Control directory must be a private, non-symlink directory owned by you")
        self.session = None
        self.action_id = 0

    def call(self, name, **arguments):
        data = json.dumps({"tool": name, "arguments": arguments}, allow_nan=False).encode() + b"\n"
        if len(data) > 1_048_576:
            raise ValueError("Request exceeds 1 MiB")
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as sock:
            sock.settimeout(5)
            sock.connect(str(self.directory / "control.sock"))
            uid, gid = ctypes.c_uint(), ctypes.c_uint()
            if ctypes.CDLL(None).getpeereid(sock.fileno(), ctypes.byref(uid), ctypes.byref(gid)) or uid.value != os.getuid():
                raise PermissionError("Unexpected simulator peer")
            sock.sendall(data)
            response = bytearray()
            while b"\n" not in response:
                chunk = sock.recv(8192)
                if not chunk:
                    raise ConnectionError("Simulator disconnected; inspect state before retrying an action")
                response.extend(chunk)
                if len(response) > 1_048_577:
                    raise ValueError("Response exceeds 1 MiB")
        result = json.loads(response.split(b"\n", 1)[0])
        if not result.get("ok"):
            raise RuntimeError(result.get("error", "Simulator error"))
        return result["data"]

    def observe(self, images=False):
        return self.call("rebot_get_observation", images=images)

    def connect(self, provenance="conventional", model_id="example-controller-v1"):
        self.session = self.call("rebot_controller_connect", provenance=provenance, model_id=model_id)
        self.action_id = 0
        return self.session["observation"]

    def action(self, observation, joints, grip):
        if self.session is None:
            raise RuntimeError("Connect first")
        result = self.call("rebot_controller_action", token=self.session["token"],
                           episode_id=observation["episode_id"], observed_frame_id=observation["frame_id"],
                           action_id=self.action_id, joints_deg=joints, gripper_mm=grip)
        self.action_id += 1
        return result["observation"]

    def wait_ready(self, timeout=20):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            state = self.call("rebot_get_evaluation")
            if state["phase"] == "ready":
                return state
            if state["phase"] == "invalid":
                raise RuntimeError(state["error"])
            time.sleep(0.1)
        raise TimeoutError("Episode did not settle")

    def release(self):
        self.call("rebot_experiment_control", action="takeover")
        self.session = None


def pose_above_cube(task, clearance):
    import math
    yaw = math.radians(task["cube_yaw_deg"]) / 2
    h = math.sqrt(0.5)
    return {"position_mm": [*task["cube_xy_mm"], -1 + task["cube_size_mm"] / 2 + clearance],
            "quaternion_xyzw": [-math.sin(yaw) * h, math.cos(yaw) * h, math.sin(yaw) * h, math.cos(yaw) * h]}


def conventional_pickup(client, task, report=None):
    """Privileged conventional baseline, explicitly separate from MaleCNS evaluation."""
    client.call("rebot_experiment_control", action="start")
    obs = client.connect()
    last_image = time.monotonic()

    def record_images():
        nonlocal obs, last_image
        if time.monotonic()-last_image >= 0.5:
            obs = client.observe(images=True)
            last_image = time.monotonic()

    def move(clearance, grip, timeout=20):
        nonlocal obs
        target = client.call("rebot_solve_pose", pose=pose_above_cube(task, clearance), frame="grasp", gripper_mm=grip)["joints_deg"]
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            obs = client.action(obs, target, grip)
            record_images()
            if max(abs(a-b) for a, b in zip(obs["joints_deg"], target)) < 0.15 and abs(obs["gripper_mm"]-grip) < 0.3:
                return
            time.sleep(0.05)
        raise TimeoutError(f"Arm did not reach clearance {clearance}")

    move(160, 90)
    move(20, 90)
    move(0, 90)
    target = obs["joints_deg"]
    deadline = time.monotonic()+5
    while time.monotonic() < deadline:
        obs = client.action(obs, target, 0)
        record_images()
        if all(obs["finger_contacts"].values()):
            break
        time.sleep(0.05)
    else:
        raise AssertionError("No bilateral finger contact at grasp")
    # Hold the closing effort while changing joint targets. The simulator reports actual aperture.
    for clearance in (20, 60, task["lift_clearance_mm"]+15):
        target = client.call("rebot_solve_pose", pose=pose_above_cube(task, clearance), frame="grasp", gripper_mm=obs["gripper_mm"])["joints_deg"]
        deadline=time.monotonic()+20
        while time.monotonic()<deadline:
            obs=client.action(obs,target,0)
            record_images()
            if max(abs(a-b) for a,b in zip(obs["joints_deg"],target)) < 0.15:
                break
            time.sleep(0.05)
        else:
            raise TimeoutError("Lift motion did not complete")
    deadline=time.monotonic()+task["hold_seconds"]+10
    while time.monotonic()<deadline:
        obs=client.action(obs,target,0)
        record_images()
        state=client.call("rebot_get_evaluation")
        if report:
            report(state)
        if state["success"]:
            return state, obs
        time.sleep(0.1)
    raise AssertionError(f"Hold failed: {state}")
