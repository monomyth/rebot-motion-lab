#!/usr/bin/env python3
"""Inspect a recorded run and export its camera frames. Does not re-simulate physics."""
import argparse
import base64
import json
from pathlib import Path

parser=argparse.ArgumentParser()
parser.add_argument("recording",type=Path)
parser.add_argument("--frames",type=Path,help="Optional destination for recorded JPEG frames")
args=parser.parse_args()
manifest=json.loads((args.recording/"manifest.json").read_text())
counts={}; last=None
if args.frames:
    args.frames.mkdir(parents=True,exist_ok=True)
for line in (args.recording/"events.jsonl").open():
    event=json.loads(line); kind=event["type"]; counts[kind]=counts.get(kind,0)+1
    if "evaluator" in event:
        last=event["evaluator"]
    if args.frames and kind=="observation":
        observation=event["policy"]
        for image in observation.get("images",[]):
            name=f'{observation["episode_id"]}-{observation["frame_id"]:08d}-{image["name"]}.jpg'
            (args.frames/name).write_bytes(base64.b64decode(image["jpeg_base64"],validate=True))
print(json.dumps({"manifest":manifest,"event_counts":counts,"last_evaluation":last},indent=2))
