import {clampPose} from './robot';
export type Pose={id:string;name:string;q:number[];grip:number};
export function smooth(t:number){t=Math.max(0,Math.min(1,t));return t*t*t*(t*(t*6-15)+10)}
export function duration(from:number[],to:number[],gripFrom:number,gripTo:number){return Math.max(.6,1.875*Math.max(...from.map((v,i)=>Math.abs(to[i]-v)))/60,1.875*Math.abs(gripTo-gripFrom)/60)}
export function interpolate(from:number[],to:number[],gripFrom:number,gripTo:number,t:number){const s=smooth(t);return {q:clampPose(from.map((v,i)=>v+(to[i]-v)*s)),grip:gripFrom+(gripTo-gripFrom)*s}}
