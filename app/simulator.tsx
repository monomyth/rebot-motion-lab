'use client';
import {useMemo,useState,useRef,useEffect,useLayoutEffect} from 'react';
import * as THREE from 'three';
import {Bot,ArrowUpRight,RotateCcw,Grid2X2,Axis3D,Mouse,Move,Focus,Play,Pause,Plus,Download,X,Route,Square,LocateFixed} from 'lucide-react';
import {Slider} from '@/components/ui/slider';
import {Tabs,TabsList,TabsTrigger,TabsContent} from '@/components/ui/tabs';
import {Robot,HOME,ARM_JOINTS,DEG,PRESETS,clampPose} from '@/lib/robot';
import {duration,interpolate,type Pose} from '@/lib/motion';
import RobotScene from './robot-scene';
const NAMES=['Base rotation','Shoulder','Elbow','Wrist pitch','Wrist yaw','Wrist roll'];
type Motion={from:number[];fromGrip:number;targets:Pose[];index:number;elapsed:number;seconds:number};
const initialSequence:Pose[]=[{id:'ready',name:'Ready',q:HOME.slice(),grip:60},{id:'reach',name:'Reach left',q:[-35,-125,-115,30,0,0],grip:60},{id:'close',name:'Close gripper',q:[-35,-125,-115,30,0,0],grip:0},{id:'lift',name:'Lift & turn',q:[35,-90,-105,15,0,0],grip:0},{id:'release',name:'Release',q:[35,-90,-105,15,0,0],grip:60}];
export default function Simulator(){
 const [q,setQ]=useState(HOME),[grip,setGrip]=useState(60),[ready,setReady]=useState(false),[error,setError]=useState(''),[grid,setGrid]=useState(true),[axes,setAxes]=useState(true),[trace,setTrace]=useState(false),[view,setView]=useState('Orbit'),[viewKey,setViewKey]=useState(0),[mode,setMode]=useState('joints');
 const [sequence,setSequence]=useState<Pose[]>(initialSequence),[running,setRunning]=useState(false),[paused,setPaused]=useState(false),[activeIndex,setActiveIndex]=useState(-1),[speed,setSpeed]=useState(50),[message,setMessage]=useState('Adjust a joint or play the example sequence.'),[target,setTarget]=useState(['300','0','350']),[ikMessage,setIkMessage]=useState(''),[ikError,setIkError]=useState(false);
 const current=useRef({q,grip,speed});useLayoutEffect(()=>{current.current={q,grip,speed}},[q,grip,speed]);const motion=useRef<Motion|null>(null),isPaused=useRef(false),id=useRef(0);
 const robot=useMemo(()=>new Robot(),[]);robot.set(q,grip);const pos=robot.position();
 const stop=()=>{motion.current=null;isPaused.current=false;setRunning(false);setPaused(false);setActiveIndex(-1)};
 const start=(targets:Pose[],isSequence=false)=>{
  if(!ready||error||!targets.length)return;const c=current.current;motion.current={from:c.q.slice(),fromGrip:c.grip,targets,index:0,elapsed:0,seconds:duration(c.q,targets[0].q,c.grip,targets[0].grip)};isPaused.current=false;setPaused(false);setRunning(true);setActiveIndex(isSequence?0:-1);setMessage(isSequence?'Playing motion sequence.':'Moving to '+targets[0].name.toLowerCase()+'.');
 };
 useEffect(()=>{
  let frame=0,previous=0;const tick=(now:number)=>{
   const dt=previous?Math.min((now-previous)/1000,.1):0;previous=now;const m=motion.current;
   if(m&&!isPaused.current){
    m.elapsed+=dt*current.current.speed/100;const to=m.targets[m.index],t=Math.min(1,m.elapsed/m.seconds),p=interpolate(m.from,to.q,m.fromGrip,to.grip,t);current.current={...current.current,...p};setQ(p.q);setGrip(p.grip);
    if(t>=1){if(m.index+1<m.targets.length){m.index++;m.from=to.q.slice();m.fromGrip=to.grip;m.elapsed=0;const next=m.targets[m.index];m.seconds=duration(m.from,next.q,m.fromGrip,next.grip);setActiveIndex(m.index);setMessage('Moving to '+next.name.toLowerCase()+'.')}else{motion.current=null;setRunning(false);setActiveIndex(-1);setMessage('Motion complete.')}}
   }frame=requestAnimationFrame(tick)
  };frame=requestAnimationFrame(tick);return()=>cancelAnimationFrame(frame)
 },[]);
 useEffect(()=>{const key=(e:KeyboardEvent)=>{if(e.key==='Escape'){motion.current=null;isPaused.current=false;setRunning(false);setPaused(false);setActiveIndex(-1);setMessage('Motion stopped at the current pose.')}};window.addEventListener('keydown',key);return()=>window.removeEventListener('keydown',key)},[]);
 const change=(i:number,v:number)=>{stop();setQ(old=>clampPose(old.map((n,j)=>i===j?v:n)));setMessage(NAMES[i]+' adjusted.');setIkMessage('')};
 const movePose=(name:string,q2:number[],g=grip)=>start([{id:'preset',name,q:clampPose(q2),grip:g}]);
 const reset=()=>{stop();setQ(HOME.slice());setGrip(60);current.current={...current.current,q:HOME.slice(),grip:60};setIkMessage('');setMessage('Ready pose restored.')};
 const solve=()=>{
  const xyz=target.map(Number);if(target.some(s=>!s.trim())||xyz.some(n=>!Number.isFinite(n))){setIkError(true);setIkMessage('Enter a finite X, Y and Z position in millimeters.');return}
  const result=robot.solve(new THREE.Vector3(...xyz.map(n=>n/1000) as [number,number,number]));setIkError(!result.success);
  if(result.success){setIkMessage('Target solved · '+(result.error*1000).toFixed(2)+' mm position error.');movePose('target position',result.q)}else setIkMessage('No solution found within 2 mm from this pose. Try a closer target or a different starting pose. The arm has not moved.');
 };
 const capture=()=>{const n=++id.current;setSequence(s=>[...s,{id:'captured-'+n,name:'Pose '+n,q:q.slice(),grip}]);setMessage('Current pose added to the sequence.')};
 const exportSequence=()=>{
  const data={format:'rebot-motion-lab-v1',robot:'B601-DM',simulation:'kinematic',angle_unit:'degrees',gripper_unit:'mm',speed_percent:speed,interpolation:'quintic smoothstep',joint_order:ARM_JOINTS.map(j=>j.name),poses:sequence.map(({name,q,grip})=>({name,joints:q,gripper_opening:grip}))};const url=URL.createObjectURL(new Blob([JSON.stringify(data,null,2)],{type:'application/json'}));const a=document.createElement('a');a.href=url;a.download='b601-dm-sequence.json';a.click();setTimeout(()=>URL.revokeObjectURL(url),1000);setMessage('Sequence exported as JSON.');
 };
 const togglePause=()=>{isPaused.current=!isPaused.current;setPaused(isPaused.current);setMessage(isPaused.current?'Playback paused.':'Playback resumed.')};
 const setCamera=(name:string)=>{setView(name);setViewKey(n=>n+1)};
 const canMove=ready&&!error;
 return <main className="app-shell">
  <header className="topbar"><div className="brand"><div className="brand-mark"><Bot/></div><h1>reBot <span>/ Motion Lab</span></h1></div><div className="top-actions"><a href="https://wiki.seeedstudio.com/rebot_arm_b601_dm_web_simulator_developer_guide/" target="_blank" rel="noreferrer">Robot documentation <ArrowUpRight/></a><div className="badge"><i className="dot"/>Simulation only</div></div></header>
  <div className="workspace-heading"><div><div className="eyebrow">Robot workspace</div><h2>B601-DM</h2></div><div className="toolbar-group">{running&&<button className="secondary stop-button" onClick={()=>{stop();setMessage('Motion stopped at the current pose.')}}><Square/>Stop</button>}<button className="secondary" onClick={reset}><RotateCcw/>Reset pose</button></div></div>
  <section className="workspace" aria-label="Robot simulator">
   <div className="viewport"><RobotScene options={{q,grip,grid,axes,trace,view,viewKey}} onReady={()=>setReady(true)} onError={s=>{setError(s);stop()}}/>
    <div className="viewport-caption"><strong>{view==='Orbit'?'Perspective':view} view</strong><p>6 axes + parallel gripper</p></div>
    <div className="view-controls"><button title="Toggle grid" aria-label="Toggle grid" aria-pressed={grid} className={'icon-button '+(grid?'active':'')} onClick={()=>setGrid(!grid)}><Grid2X2/></button><button title="Toggle tool axes" aria-label="Toggle tool axes" aria-pressed={axes} className={'icon-button '+(axes?'active':'')} onClick={()=>setAxes(!axes)}><Axis3D/></button><button title="Trace tool path" aria-label="Trace tool path" aria-pressed={trace} className={'icon-button '+(trace?'active':'')} onClick={()=>setTrace(!trace)}><Route/></button><button title="Reset camera" aria-label="Reset camera" className="icon-button" onClick={()=>setCamera('Orbit')}><Focus/></button></div>
    <div className="camera-views">{['Orbit','Front','Top'].map(v=><button key={v} aria-pressed={view===v} className={view===v?'selected':''} onClick={()=>setCamera(v)}>{v}</button>)}</div>
    <div className="axis-key"><span>X</span><span>Y</span><span>Z</span></div><div className="viewport-help"><span><Mouse/>Drag to orbit</span><span><Move/>Right-drag to pan</span><span>Scroll to zoom</span></div>
    {(!ready||error)&&<output className="model-state"><Bot/>{error||'Loading B601-DM geometry…'}{error&&<button className="secondary" onClick={()=>window.location.reload()}>Reload model</button>}</output>}
   </div>
   <aside className="control-panel"><div className="panel-title"><h3>Motion controls</h3><span className="mono">B601-DM</span></div>
    <Tabs value={mode} onValueChange={v=>setMode(String(v))} className="control-tabs"><TabsList><TabsTrigger value="joints">Joints</TabsTrigger><TabsTrigger value="target">Target position</TabsTrigger></TabsList>
     <TabsContent value="joints">{ARM_JOINTS.map((j,i)=><div className="joint-row" key={j.name}><div className="joint-header"><label className="joint-label" htmlFor={j.name}><b className="mono">J{i+1}</b>{NAMES[i]}</label><div className="joint-number mono"><input id={j.name} aria-label={NAMES[i]+' angle'} type="number" step="1" min={j.lower/DEG} max={j.upper/DEG} value={Math.round(q[i]*10)/10} disabled={running} onChange={e=>change(i,Number(e.target.value))}/><span>°</span></div></div><Slider className="joint-slider" aria-label={NAMES[i]} disabled={running} min={j.lower/DEG} max={j.upper/DEG} step={.1} value={[q[i]]} onValueChange={v=>change(i,Array.isArray(v)?v[0]:v)}/><div className="joint-range mono"><span>{(j.lower/DEG).toFixed(1)}°</span><span>{(j.upper/DEG).toFixed(1)}°</span></div></div>)}</TabsContent>
     <TabsContent value="target"><div className="ik-panel"><p>Move the gripper tip to a position in the robot’s base frame.</p><div className="ik-fields">{['X','Y','Z'].map((a,i)=><label key={a} htmlFor={'target-'+a}>{a} · mm<input id={'target-'+a} type="number" step="10" value={target[i]} onChange={e=>{setTarget(v=>v.map((x,j)=>i===j?e.target.value:x));setIkMessage('')}}/></label>)}</div><button className="primary" disabled={!canMove||running} onClick={solve}><LocateFixed/>Solve & move</button><button className="secondary" onClick={()=>{setTarget(pos.toArray().map(n=>(n*1000).toFixed(1)));setIkMessage('')}}>Use current position</button>{ikMessage&&<output className={'ik-message '+(ikError?'error':'')}>{ikMessage}</output>}<p className="solver-note">Position-only inverse kinematics. Wrist orientation is free. Joint limits are enforced; collisions and forces are not simulated.</p></div></TabsContent>
    </Tabs>
    <div className="gripper"><div className="joint-header"><span>Gripper opening</span><span className="mono">{grip.toFixed(0)} <span className="footnote">mm</span></span></div><Slider className="joint-slider" aria-label="Gripper opening" disabled={running} min={0} max={90} step={1} value={[grip]} onValueChange={v=>setGrip(Array.isArray(v)?v[0]:v)}/><div className="joint-range"><span>Closed</span><span>90 mm</span></div></div>
    <div className="preset-row">{PRESETS.map(p=><button key={p.name} className="secondary" disabled={!canMove||running} onClick={()=>movePose(p.name,p.q)}>{p.name}</button>)}</div>
   </aside>
   <div className="telemetry"><div><p>TOOL CENTER POINT</p><span className="footnote">Base frame · millimeters</span></div>{['X','Y','Z'].map((a,i)=><div key={a}><p>{a} POSITION</p><strong className="mono">{(pos.toArray()[i]*1000).toFixed(1)}</strong><small>mm</small></div>)}</div>
   <div className="panel-bottom"><button className="primary" disabled={!canMove||running} onClick={capture}><Plus/>Add pose to sequence</button></div>
  </section>
  <section className="trajectory" aria-label="Motion sequence"><div className="trajectory-head"><div><div className="section-kicker"><Route/><h3>Motion sequence</h3><span className="count mono">{sequence.length} poses</span></div><p>Teach a pose. Connect the movement.</p></div><div className="trajectory-actions"><div className="speed-control"><span>Speed</span><Slider aria-label="Playback speed" className="joint-slider" value={[speed]} min={10} max={100} step={10} onValueChange={v=>setSpeed(Array.isArray(v)?v[0]:v)}/><span className="mono">{speed}%</span></div><button className="icon-button" title="Export sequence as JSON" aria-label="Export sequence as JSON" disabled={!sequence.length} onClick={exportSequence}><Download/></button><button className="secondary" disabled={!sequence.length||running} onClick={()=>{setSequence([]);setMessage('Sequence cleared. Add a pose to begin.')}}>Clear</button><button className="primary" disabled={!canMove||!sequence.length} onClick={()=>{if(running)togglePause();else start(sequence,true)}}>{running&&!paused?<Pause/>:<Play/>}{running?(paused?'Resume':'Pause'):'Play sequence'}</button></div></div>
   <div className="waypoints">{sequence.length?sequence.map((p,i)=><div className={'waypoint '+(activeIndex===i?'playing':'')} key={p.id}><button aria-label={'Move to '+p.name} disabled={running||!canMove} className="pose-button" onClick={()=>movePose(p.name,p.q,p.grip)}><span className="waypoint-number">{String(i+1).padStart(2,'0')}</span><span><b>{p.name}</b><p>Gripper {p.grip.toFixed(0)} mm</p></span></button><button className="remove" title={'Remove '+p.name} aria-label={'Remove '+p.name} disabled={running} onClick={()=>setSequence(s=>s.filter(x=>x.id!==p.id))}><X/></button></div>):<div className="sequence-empty">Move the arm, then select “Add pose to sequence” to record your first waypoint.</div>}</div>
  </section>
  <footer className="statusline"><output className="status"><i className="dot"/>{error?'Model unavailable':!ready?'Loading model':message}</output><span>Joint limits on · No collision or force simulation<br/><a href="/model/NOTICE.txt" target="_blank" rel="noreferrer">Seeed model · CERN-OHL-W-2.0</a></span></footer>
 </main>
}
