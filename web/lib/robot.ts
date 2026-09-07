import * as THREE from 'three';
import model from './model.json';
export const DEG = Math.PI / 180;
export const ARM_JOINTS = model.joints.filter(j => j.type === 'revolute');
export const HOME = [0, -95, -95, 10, 0, 0];
export const PRESETS = [
 {name:'Ready', q:HOME},
 {name:'Reach', q:[0,-140,-155,20,0,0]},
 {name:'Upright', q:[0,-90,-179.8,0,0,0]},
];
export function clampPose(q:number[]) {return ARM_JOINTS.map((j,i)=>THREE.MathUtils.clamp(Number.isFinite(q[i])?q[i]:HOME[i],j.lower/DEG,j.upper/DEG))}
export class Robot {
 root=new THREE.Group(); links:Record<string,THREE.Group>={}; joints:Record<string,THREE.Group>={}; tcp=new THREE.Object3D(); q=HOME.slice();grip=60;
 constructor(){
  for(const l of model.links){this.links[l.name]=new THREE.Group();this.links[l.name].name=l.name}
  this.root.add(this.links.base_link);
  for(const j of model.joints){
   const origin=new THREE.Group(); origin.position.fromArray(j.xyz);origin.quaternion.setFromEuler(new THREE.Euler(j.rpy[0],j.rpy[1],j.rpy[2],'ZYX'));
   const motion=new THREE.Group();origin.add(motion);motion.add(this.links[j.child]);this.links[j.parent].add(origin);this.joints[j.name]=motion;
  }
  // The source end_link is the fingertip center at closed aperture.
  this.links.end_link.add(this.tcp); this.set(HOME,60);
 }
 set(q:number[],grip:number){
  this.q=clampPose(q);this.grip=THREE.MathUtils.clamp(grip,0,90);
  ARM_JOINTS.forEach((j,i)=>this.joints[j.name].quaternion.setFromAxisAngle(new THREE.Vector3(...j.axis as [number,number,number]),this.q[i]*DEG));
  this.joints.finger_left.position.set(0,this.grip/2000,0);this.joints.finger_right.position.set(0,-this.grip/2000,0);this.root.updateMatrixWorld(true);
 }
 position(){return this.tcp.getWorldPosition(new THREE.Vector3())}
 // Position-only damped least-squares IK; wrist orientation stays unconstrained.
 solve(target:THREE.Vector3,initial=this.q,maxIterations=300){
  const saved=this.q.slice(), aperture=this.grip;let q=clampPose(initial),error=Infinity;
  for(let it=0;it<maxIterations;it++){
   this.set(q,aperture);const p=this.position(),e=target.clone().sub(p);error=e.length();if(error<.001)break;
   const cols:THREE.Vector3[]=[];
   for(let j=0;j<6;j++){
    const qq=q.slice(),h=q[j]+.01<=ARM_JOINTS[j].upper/DEG?.01:-.01;qq[j]+=h;this.set(qq,aperture);cols.push(this.position().sub(p).multiplyScalar(1/(h*DEG)));
   }
   const a=new THREE.Matrix3();const v=Array(9).fill(0);for(const c of cols){const w=c.toArray();for(let r=0;r<3;r++)for(let s=0;s<3;s++)v[r*3+s]+=w[r]*w[s]}
   v[0]+=.0004;v[4]+=.0004;v[8]+=.0004;a.set(...v as [number,number,number,number,number,number,number,number,number]);a.invert();const step=e.applyMatrix3(a);
   q=clampPose(q.map((n,j)=>n+THREE.MathUtils.clamp(cols[j].dot(step),-.12,.12)/DEG));
  }
  this.set(q,aperture);error=this.position().distanceTo(target);this.set(saved,aperture);return {q,error,success:error<.002};
 }
}
export { model };
