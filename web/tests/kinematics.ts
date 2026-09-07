import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import * as THREE from 'three';
import {Robot,HOME,DEG,ARM_JOINTS,PRESETS,model,clampPose} from '../lib/robot';
import {duration,interpolate} from '../lib/motion';
const robot=new Robot();const initial=robot.position();
console.log('Ready TCP in mm:',initial.toArray().map(n=>+(n*1000).toFixed(2)));
// A +90 degree base rotation must map x -> y and y -> -x, preserving height.
robot.set([90,...HOME.slice(1)],60);const p=robot.position();assert.ok(p.distanceTo(new THREE.Vector3(ARM_JOINTS[0].xyz[0]-initial.y,initial.x-ARM_JOINTS[0].xyz[0],initial.z))<1e-9);
robot.set(HOME,90);assert.equal(robot.joints.finger_left.position.y,.045);assert.equal(robot.joints.finger_right.position.y,-.045);assert.ok(robot.position().distanceTo(initial)<1e-10);
for(const preset of PRESETS){robot.set(preset.q,60);const p=robot.position();console.log(preset.name,'TCP mm',p.toArray().map(n=>+(n*1000).toFixed(1)));assert.ok(p.z>0);}
for(let k=0;k<12;k++){
 const known=HOME.map((n,i)=>n+Math.sin(k+i)*8);robot.set(known,60);const target=robot.position();robot.set(HOME,60);const s=robot.solve(target);assert.ok(s.success,'Known reachable target '+k+' error '+s.error);assert.ok(robot.position().distanceTo(initial)<1e-9,'Solver must not mutate arm');robot.set(s.q,60);assert.ok(robot.position().distanceTo(target)<.002);s.q.forEach((n,i)=>assert.ok(n>=ARM_JOINTS[i].lower/DEG&&n<=ARM_JOINTS[i].upper/DEG));
}
robot.set(HOME,60);const unreachable=robot.solve(new THREE.Vector3(5,5,5));assert.equal(unreachable.success,false);assert.ok(robot.position().distanceTo(initial)<1e-9);
const clamped=clampPose([999,-999,999,-999,999,-999]);clamped.forEach((n,i)=>assert.ok(n>=ARM_JOINTS[i].lower/DEG&&n<=ARM_JOINTS[i].upper/DEG));
const end=[-35,-125,-115,30,0,0],seconds=duration(HOME,end,60,0);assert.deepEqual(interpolate(HOME,end,60,0,0),{q:HOME,grip:60});assert.deepEqual(interpolate(HOME,end,60,0,1),{q:end,grip:0});
let previous=interpolate(HOME,end,60,0,0);for(let i=1;i<=1000;i++){const p=interpolate(HOME,end,60,0,i/1000),dt=seconds/1000;p.q.forEach((n,j)=>assert.ok(Math.abs(n-previous.q[j])/dt<=60.001));assert.ok(Math.abs(p.grip-previous.grip)/dt<=60.001);previous=p}
let files=0,triangles=0;
for(const link of model.links)for(const visual of link.visuals){const b=fs.readFileSync(path.resolve('public/model',visual.mesh));const count=b.readUInt32LE(80);assert.equal(b.length,84+50*count,visual.mesh);files++;triangles+=count;}
console.log('PASS: base rotation, gripper mimic, positive-height presets, 12 reachable IK targets, unreachable target, limits, non-mutating IK, motion endpoints and velocity bound.');console.log('PASS:',files,'STL assets validated;',triangles,'triangles.');
