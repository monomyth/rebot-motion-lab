import {build} from 'esbuild';
import {mkdir} from 'node:fs/promises';
import {spawnSync} from 'node:child_process';
await mkdir('work', {recursive: true});
for (const name of ['kinematics', 'floor']) {
  const output = `work/${name}-test.mjs`;
  await build({entryPoints: [`tests/${name}.ts`], bundle: true, platform: 'node', format: 'esm', outfile: output});
  const result = spawnSync(process.execPath, [output], {stdio: 'inherit'});
  if (result.status !== 0) process.exit(result.status ?? 1);
}
