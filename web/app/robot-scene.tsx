'use client';
import {useEffect,useRef,useLayoutEffect} from 'react';
import * as THREE from 'three';
import {OrbitControls} from 'three/addons/controls/OrbitControls.js';
import {STLLoader} from 'three/addons/loaders/STLLoader.js';
import {Robot,model} from '@/lib/robot';
export type SceneOptions={q:number[];grip:number;grid:boolean;axes:boolean;trace:boolean;view:string;viewKey:number;cube?:{present:boolean;x:number;y:number;z:number;size:number;yaw:number}};
export default function RobotScene({options,onReady,onError}:{options:SceneOptions;onReady:()=>void;onError:(s:string)=>void}){
 const mount=useRef<HTMLDivElement>(null),state=useRef(options),callbacks=useRef({onReady,onError});useLayoutEffect(()=>{state.current=options;callbacks.current={onReady,onError}},[options,onReady,onError]);
 useEffect(()=>{
  const el=mount.current!;let disposed=false,frame=0;const resources:THREE.BufferGeometry[]=[],materials:THREE.Material[]=[];
  let renderer:THREE.WebGLRenderer;try{renderer=new THREE.WebGLRenderer({antialias:true,alpha:false,powerPreference:'high-performance'})}catch{callbacks.current.onError('A WebGL-capable browser is required for the 3D model.');return}
  renderer.setPixelRatio(Math.min(window.devicePixelRatio,2));renderer.setClearColor(0x202720);renderer.outputColorSpace=THREE.SRGBColorSpace;renderer.toneMapping=THREE.ACESFilmicToneMapping;renderer.toneMappingExposure=1.35;el.appendChild(renderer.domElement);
  renderer.domElement.setAttribute('aria-label','Interactive 3D B601-DM robot. Drag to orbit; scroll to zoom.');
  const scene=new THREE.Scene();scene.fog=new THREE.Fog(0x202720,2.5,5);
  const camera=new THREE.PerspectiveCamera(38,1,.005,20);camera.up.set(0,0,1);camera.position.set(1.08,-1.55,1.04);
  const controls=new OrbitControls(camera,renderer.domElement);controls.target.set(.18,0,.22);controls.enableDamping=true;controls.minDistance=.25;controls.maxDistance=3;controls.maxPolarAngle=Math.PI*.49;
  scene.add(new THREE.HemisphereLight(0xf0ffe0,0x53644b,2.1));const sun=new THREE.DirectionalLight(0xffffff,3.3);sun.position.set(1,-1,2);scene.add(sun);const rim=new THREE.DirectionalLight(0xc3e78c,2);rim.position.set(-1,1,1);scene.add(rim);
  const groundGeo=new THREE.PlaneGeometry(20,20),groundMat=new THREE.MeshStandardMaterial({color:0x263023,roughness:1,metalness:0});resources.push(groundGeo);materials.push(groundMat);const ground=new THREE.Mesh(groundGeo,groundMat);ground.position.z=-.001;scene.add(ground);
  const cubeGeo=new THREE.BoxGeometry(.04,.04,.04);resources.push(cubeGeo);const cubeMat=new THREE.MeshStandardMaterial({color:0xc45c26,roughness:.45,metalness:.05});materials.push(cubeMat);const cubeMesh=new THREE.Mesh(cubeGeo,cubeMat);cubeMesh.position.set(.28,0,.019);scene.add(cubeMesh);
  const grid=new THREE.GridHelper(2.4,24,0x627448,0x3d4c33);grid.rotation.x=Math.PI/2;grid.position.z=.0005;scene.add(grid);
  const robot=new Robot();scene.add(robot.root);
  const axes=new THREE.AxesHelper(.12);robot.tcp.add(axes);
  const ringGeo=new THREE.RingGeometry(.058,.060,80);const ringMat=new THREE.MeshBasicMaterial({color:0x95ad66,side:THREE.DoubleSide});resources.push(ringGeo);materials.push(ringMat);const ring=new THREE.Mesh(ringGeo,ringMat);ring.position.z=.001;scene.add(ring);
  const trailGeo=new THREE.BufferGeometry();resources.push(trailGeo);const trailMat=new THREE.LineBasicMaterial({color:0xc3e85a,transparent:true,opacity:.7});materials.push(trailMat);const trail=new THREE.Line(trailGeo,trailMat);scene.add(trail);const points:THREE.Vector3[]=[];
  const loader=new STLLoader();
  Promise.all(model.links.flatMap(l=>l.visuals.map(async v=>{
   const geometry=await loader.loadAsync('/model/'+v.mesh);if(disposed){geometry.dispose();return}resources.push(geometry);
   const rgba=(model.materials as Record<string,number[]>)[v.material];const color=new THREE.Color().setRGB(rgba[0],rgba[1],rgba[2],THREE.SRGBColorSpace);
   const material=new THREE.MeshStandardMaterial({color,roughness:v.material.includes('metal')?.4:.62,metalness:v.material.includes('metal')?.6:.18});materials.push(material);
   const mesh=new THREE.Mesh(geometry,material);mesh.position.fromArray(v.xyz);mesh.quaternion.setFromEuler(new THREE.Euler(v.rpy[0],v.rpy[1],v.rpy[2],'ZYX'));robot.links[l.name].add(mesh);
  }))).then(()=>{if(!disposed)callbacks.current.onReady()}).catch(()=>{if(!disposed)callbacks.current.onError('The robot model could not load. Reload to try again.')});
  const resize=()=>{const {width,height}=el.getBoundingClientRect();renderer.setSize(width,height);camera.aspect=width/Math.max(height,1);camera.updateProjectionMatrix()};const ro=new ResizeObserver(resize);ro.observe(el);resize();let previousView=-1,lastTrace=false;
  const render=()=>{
   if(disposed)return;const s=state.current;robot.set(s.q,s.grip);grid.visible=s.grid;axes.visible=s.axes;trail.visible=s.trace;
   const cube=s.cube||{present:true,x:.28,y:0,z:.019,size:.04,yaw:0};
   cubeMesh.visible=cube.present;cubeMesh.position.set(cube.x,cube.y,cube.z);cubeMesh.scale.setScalar(cube.size/.04);cubeMesh.rotation.z=cube.yaw;
   if(previousView!==s.viewKey){previousView=s.viewKey;controls.target.set(.18,0,.22);if(s.view==='Top')camera.position.set(.18,-.001,1.45);else if(s.view==='Front')camera.position.set(.18,-1.55,.42);else camera.position.set(1.08,-1.55,1.04);controls.update()}
   if(s.trace){const p=robot.position();if(!lastTrace)points.length=0;if(!points.length||points[points.length-1].distanceTo(p)>.003){points.push(p);if(points.length>1200)points.shift();trailGeo.setFromPoints(points)}}lastTrace=s.trace;
   controls.update();renderer.render(scene,camera);frame=requestAnimationFrame(render)
  };render();const lost=(e:Event)=>{e.preventDefault();callbacks.current.onError('The 3D graphics context was lost. Reload to restore it.')};renderer.domElement.addEventListener('webglcontextlost',lost);
  return()=>{disposed=true;cancelAnimationFrame(frame);ro.disconnect();controls.dispose();resources.forEach(g=>g.dispose());materials.forEach(m=>m.dispose());grid.geometry.dispose();(grid.material as THREE.Material).dispose();axes.geometry.dispose();(axes.material as THREE.Material).dispose();renderer.dispose();renderer.domElement.remove();}
 },[]);
 return <div className="scene-mount" ref={mount}/>;
}
