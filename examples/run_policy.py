#!/usr/bin/env python3
"""Run an external policy through the simulator's observation/action contract.

The supplied factory returns an object with reset(observation) and act(observation).
act returns {"joints_deg": [six angles], "gripper_mm": opening}. No neural model is
bundled or claimed here. The factory is responsible for loading MaleCNS, encoding
images/state, computing neural dynamics, and decoding its output.
"""
import argparse
import importlib
import json
import time
from controller_client import ReBotClient


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument("--control-directory",required=True)
    parser.add_argument("--policy",required=True,help="Python module:factory for your external policy")
    parser.add_argument("--model-id",required=True,help="Checkpoint and preprocessing identifier for the run log")
    parser.add_argument("--provenance",choices=["malecns","teacher_assisted","conventional"],default="malecns")
    parser.add_argument("--state-only",action="store_true",help="Only for a task explicitly configured with state observations")
    parser.add_argument("--hz",type=float,default=10)
    args=parser.parse_args()
    if not 1 <= args.hz <= 30:
        parser.error("--hz must be between 1 and 30")
    module,factory=args.policy.split(":",1)
    policy=getattr(importlib.import_module(module),factory)()
    client=ReBotClient(args.control_directory)
    # Setup/evaluation objects never enter the policy's input.
    client.call("rebot_reset_episode"); client.wait_ready()
    first=client.observe(images=not args.state_only)
    if args.state_only and first["input_mode"] != "state":
        raise ValueError("State-only runner requires an explicitly state-assisted task")
    policy.reset(first)
    client.call("rebot_recording",action="start")
    client.call("rebot_experiment_control",action="start")
    client.connect(provenance=args.provenance,model_id=args.model_id)
    try:
        while True:
            started=time.monotonic()
            observation=client.observe(images=not args.state_only)
            if observation["phase"] != "running":
                break
            action=policy.act(observation)
            client.action(observation,action["joints_deg"],action["gripper_mm"])
            time.sleep(max(0,1/args.hz-(time.monotonic()-started)))
    finally:
        client.release()
        recording=client.call("rebot_recording",action="stop")
        print(json.dumps({"evaluation":client.call("rebot_get_evaluation"),"recording":recording},indent=2))


if __name__=="__main__": main()
