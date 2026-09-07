import * as THREE from 'three';
import {Robot, ARM_JOINTS, DEG, model} from './robot';
import supportData from './floor-hulls.json';
export const FLOOR_HEIGHT = -0.001;
const MARGIN = 0.000001;
export type FloorPose = {q: number[]; grip: number};
const supports = supportData.links.map(link => ({name: link.name, points: link.vertices.map(p => new THREE.Vector3(...p as [number, number, number]))}));
const descendants = ARM_JOINTS.map(joint => {
  const names = new Set([joint.child]);
  for (const child of model.joints) if (names.has(child.parent)) names.add(child.child);
  return names;
});
const radiusBound = model.joints.reduce((sum, joint) => sum + Math.hypot(...joint.xyz), 0)
  + Math.max(...supports.flatMap(h => h.points.map(p => p.length()))) + 0.09;
const blend = (a: FloorPose, b: FloorPose, t: number): FloorPose => ({q: a.q.map((v, i) => v + (b.q[i] - v) * t), grip: a.grip + (b.grip - a.grip) * t});

/** Support vertices preserve the exact minimum height of every moving mesh, including both fingers. */
export class FloorConstraint {
  private robot = new Robot();
  minimumHeight(pose: FloorPose) {
    this.robot.set(pose.q, pose.grip);
    let height = Infinity;
    for (const hull of supports) {
      const m = this.robot.links[hull.name].matrixWorld.elements;
      for (const p of hull.points) height = Math.min(height, m[2]*p.x + m[6]*p.y + m[10]*p.z + m[14]);
    }
    return height;
  }
  limited(from: FloorPose, to: FloorPose): FloorPose {
    const changed = from.q.map((v, i) => v !== to.q[i] ? i : -1).filter(i => i >= 0);
    if (!changed.length) {
      if (this.minimumHeight(to) >= FLOOR_HEIGHT + MARGIN) return to;
      if (this.minimumHeight(from) < FLOOR_HEIGHT) return from;
      let low = 0, high = 1;
      for (let i=0; i<32; i++) {
        const middle = (low+high)/2;
        if (this.minimumHeight(blend(from,to,middle)) >= FLOOR_HEIGHT+MARGIN) low=middle; else high=middle;
      }
      return blend(from,to,low);
    }
    if (changed.length === 1 && from.grip === to.grip) return this.limitJoint(from,to,changed[0]);
    // A second-derivative bound certifies the full interval, preventing hidden floor crossings.
    const angle=from.q.reduce((sum,v,i)=>sum+Math.abs(to.q[i]-v)*DEG,0);
    const curvature=radiusBound*angle*angle+2*angle*Math.abs(to.grip-from.grip)/2000;
    let evaluations=0;
    const walk=(a:number,b:number,ha:number,hb:number,depth:number):number=>{
      if(Math.min(ha,hb)>=MARGIN && Math.min(ha,hb)>=curvature*(b-a)*(b-a)/8)return b;
      if(depth===24||evaluations>=4096)return a;
      const m=(a+b)/2,hm=this.minimumHeight(blend(from,to,m))-FLOOR_HEIGHT;
      evaluations++;
      const first=walk(a,m,ha,hm,depth+1);
      return first<m ? first : walk(m,b,hm,hb,depth+1);
    };
    const fraction=walk(0,1,this.minimumHeight(from)-FLOOR_HEIGHT,this.minimumHeight(to)-FLOOR_HEIGHT,0);
    return fraction===1 ? to : blend(from,to,fraction);
  }
  private limitJoint(from:FloorPose,to:FloorPose,index:number):FloorPose {
    this.robot.set(from.q,from.grip);
    const origin=this.robot.joints[ARM_JOINTS[index].name].parent!.matrixWorld;
    const pivot=new THREE.Vector3().setFromMatrixPosition(origin);
    const axis=new THREE.Vector3(...ARM_JOINTS[index].axis as [number,number,number]).transformDirection(origin);
    const delta=(to.q[index]-from.q[index])*DEG,direction=delta<0?-1:1;
    let travel=Math.abs(delta);
    const offset=new THREE.Vector3(),cross=new THREE.Vector3();
    for(const hull of supports) if(descendants[index].has(hull.name)) {
      const transform=this.robot.links[hull.name].matrixWorld;
      for(const point of hull.points) {
        offset.copy(point).applyMatrix4(transform).sub(pivot);
        const parallel=axis.dot(offset),a=offset.z-axis.z*parallel,b=cross.crossVectors(axis,offset).z*direction;
        const c=pivot.z+axis.z*parallel-FLOOR_HEIGHT-MARGIN,radius=Math.hypot(a,b);
        if(radius<1e-14||c>=radius)continue;
        if(a+c < -MARGIN)return from;
        const phase=Math.atan2(b,a),root=Math.acos(THREE.MathUtils.clamp(-c/radius,-1,1));
        for(const candidate of [phase-root,phase+root]) {
          let s=candidate%(2*Math.PI);if(s < -1e-10)s+=2*Math.PI;s=Math.max(0,s);
          if(s<=travel && -a*Math.sin(s)+b*Math.cos(s)<-1e-12)travel=s;
        }
      }
    }
    return travel>=Math.abs(delta) ? to : blend(from,to,Math.max(0,travel-1e-10)/Math.abs(delta));
  }
}
