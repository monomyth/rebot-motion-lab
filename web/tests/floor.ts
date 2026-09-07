import assert from 'node:assert/strict';
import fs from 'node:fs';
import * as THREE from 'three';
import {FloorConstraint,FLOOR_HEIGHT} from '../lib/floor';
import {Robot,HOME,model} from '../lib/robot';
const floor=new FloorConstraint(),robot=new Robot();
const ready={q:HOME.slice(),grip:60};
const folded={q:[0,0,0,0,0,0],grip:0};
assert.ok(floor.minimumHeight(ready)>0 && floor.minimumHeight(folded)>0);
assert.deepEqual(floor.limited(folded,ready),ready,'startup must unfold without hitting floor');

// Independently measure original triangle vertices, including per-visual origins.
function meshHeight(pose:{q:number[];grip:number}) {
 robot.set(pose.q,pose.grip);let z=Infinity,link='';
 for(const l of model.links)if(l.name!=='base_link')for(const visual of l.visuals){
  const local=new THREE.Matrix4().compose(new THREE.Vector3(...visual.xyz as [number,number,number]),new THREE.Quaternion().setFromEuler(new THREE.Euler(...visual.rpy as [number,number,number],'ZYX')),new THREE.Vector3(1,1,1));
  const m=robot.links[l.name].matrixWorld.clone().multiply(local).elements;
  const bytes=fs.readFileSync('public/model/'+visual.mesh);
  for(let i=0;i<bytes.readUInt32LE(80);i++)for(let j=0;j<3;j++){
   const k=84+50*i+12+12*j,height=m[2]*bytes.readFloatLE(k)+m[6]*bytes.readFloatLE(k+4)+m[10]*bytes.readFloatLE(k+8)+m[14];
   if(height<z){z=height;link=l.name}
  }
 }
 return {z,link};
}
for(const roll of [-90,90]){
 const from={q:HOME.map((v,i)=>i===5?roll:v),grip:90};
 const requested={q:from.q.map((v,i)=>i===1?-179:v),grip:90};
 const stopped=floor.limited(from,requested),mesh=meshHeight(stopped);
 assert.ok(stopped.q[1]>-134 && stopped.q[1]<-132);
 assert.equal(mesh.link,roll<0?'finger_left_link':'finger_right_link','finger geometry must make first contact');
 assert.ok(mesh.z>=FLOOR_HEIGHT && mesh.z-FLOOR_HEIGHT<.000002);
 assert.ok(Math.abs(mesh.z-floor.minimumHeight(stopped))<1e-10,'hull must match every original STL vertex');
 robot.set(stopped.q,stopped.grip);assert.ok(robot.position().z>.02,'TCP alone would miss the finger collision');
 const pushed=floor.limited(stopped,requested);assert.ok(Math.abs(pushed.q[1]-stopped.q[1])<1e-6,'cannot push through contact');
 const reversed={q:stopped.q.map((v,i)=>i===1?v+2:v),grip:90};assert.deepEqual(floor.limited(stopped,reversed),reversed,'can reverse out of contact immediately');
 const rotate={q:stopped.q.map((v,i)=>i===0?100:v),grip:90};assert.deepEqual(floor.limited(stopped,rotate),rotate,'base rotation remains free at contact');
}
const closed={q:[0,-135,-95,10,0,90],grip:0};
assert.ok(floor.minimumHeight(closed)>0);
const opened=floor.limited(closed,{q:closed.q,grip:90});assert.ok(opened.grip>0 && opened.grip<90);
assert.ok(meshHeight(opened).z>=FLOOR_HEIGHT);assert.deepEqual(floor.limited(opened,closed),closed);
const a={q:[134.15847243481227,-116.72407774837623,-169.71850875742604,60.65879017574375,12.048834920242973,-116.09563604143887],grip:90};
const b={q:a.q.map((v,i)=>i===2?0:v),grip:90};
assert.ok(floor.minimumHeight(a)>.01 && floor.minimumHeight(b)>.01);
const contact=floor.limited(a,b);assert.ok(contact.q[2]<-70,'clear endpoints must not tunnel through an obstructed sweep');
for(let k=0;k<=100;k++)assert.ok(floor.minimumHeight({q:a.q.map((v,i)=>v+(contact.q[i]-v)*k/100),grip:90})>=FLOOR_HEIGHT);
const multi={q:[100,-179,-60,20,20,90],grip:90};
const multiContact=floor.limited(ready,multi);assert.notDeepEqual(multiContact,multi);
for(let k=0;k<=100;k++)assert.ok(floor.minimumHeight({q:ready.q.map((v,i)=>v+(multiContact.q[i]-v)*k/100),grip:ready.grip+(multiContact.grip-ready.grip)*k/100})>=FLOOR_HEIGHT);
const begin=performance.now();for(let k=0;k<1000;k++)floor.limited(ready,{q:ready.q.map((v,i)=>i===0?Math.sin(k)*150:v),grip:60});
console.log('PASS: both fingertip contacts, exact STL heights, reversal, base rotation, gripper travel, swept joint and coordinated moves.');
console.log('Floor-limit sample:',((performance.now()-begin)/1000).toFixed(3),'ms/input over 1,000 requests.');
