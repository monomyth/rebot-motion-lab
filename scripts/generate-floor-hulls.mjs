// Regenerate support vertices from the licensed STL geometry. Run after npm ci in web/.
// A convex hull preserves a mesh's exact minimum height against any plane.
import fs from 'node:fs';
import path from 'node:path';
import {createRequire} from 'node:module';
import {fileURLToPath} from 'node:url';
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const require = createRequire(path.join(root, 'web/package.json'));
const THREE = await import(require.resolve('three'));
const {ConvexHull} = await import(require.resolve('three/examples/jsm/math/ConvexHull.js'));
const modelRoot = path.join(root, 'Sources/RobotCore/Resources/model');
const model = JSON.parse(fs.readFileSync(path.join(modelRoot, 'model.json')));
const links = [];
for (const link of model.links) {
  if (!link.visuals.length || link.name === 'base_link') continue;
  const unique = new Map();
  for (const visual of link.visuals) {
    const transform = new THREE.Matrix4().compose(new THREE.Vector3(...visual.xyz),
      new THREE.Quaternion().setFromEuler(new THREE.Euler(...visual.rpy, 'ZYX')), new THREE.Vector3(1, 1, 1));
    const data = fs.readFileSync(path.join(modelRoot, visual.mesh));
    const count = data.readUInt32LE(80);
    if (data.length !== 84 + 50 * count) throw new Error('Malformed STL: ' + visual.mesh);
    for (let i = 0; i < count; i++) for (let j = 0; j < 3; j++) {
      const offset = 84 + i * 50 + 12 + j * 12;
      const point = new THREE.Vector3(data.readFloatLE(offset), data.readFloatLE(offset + 4), data.readFloatLE(offset + 8)).applyMatrix4(transform);
      unique.set(point.toArray().join(','), point);
    }
  }
  const hull = new ConvexHull().setFromPoints([...unique.values()]);
  const support = new Set();
  for (const face of hull.faces) {
    let edge = face.edge;
    do { support.add(edge.head().point); edge = edge.next; } while (edge !== face.edge);
  }
  const vertices = [...support].map(p => p.toArray()).sort((a,b) => a[0]-b[0] || a[1]-b[1] || a[2]-b[2]);
  links.push({name: link.name, vertices});
  console.log(link.name, unique.size, 'mesh vertices ->', vertices.length, 'support vertices');
}
const output = JSON.stringify({source: model.source, commit: model.commit, license: 'CERN-OHL-W-2.0', links}) + '\n';
for (const location of ['Sources/RobotCore/Resources/model/floor-hulls.json', 'web/lib/floor-hulls.json']) fs.writeFileSync(path.join(root, location), output);
