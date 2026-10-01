import assert from 'node:assert/strict';
import { test } from 'node:test';
import { copyFile, mkdir, mkdtemp, readFile, rm, stat, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';

const execute = promisify(execFile);
const project = 'zoccosfjulasqxczhvfm';

async function workspace(context) {
  const directory = await mkdtemp(join(tmpdir(), 'danarapi-cloud-tests-'));
  context.after(() => rm(directory, { recursive: true, force: true }));
  return directory;
}

test('deployment plan/apply never seed, reset, prune or disable JWT verification', async context => {
  for (const mode of ['plan', 'apply', 'foreign-project']) {
    const directory = await workspace(context);
    await mkdir(join(directory, 'scripts'));
    await mkdir(join(directory, 'supabase'));
    await copyFile(new URL('../../scripts/deploy-supabase.sh', import.meta.url), join(directory, 'scripts/deploy-supabase.sh'));
    await writeFile(join(directory, 'supabase/.env'), 'GEMINI_API_KEY=synthetic\n');
    await writeFile(join(directory, 'scripts/prepare-cloud-secrets.mjs'), `import{writeFile}from'node:fs/promises';await writeFile(process.argv[3],'GEMINI_API_KEY=synthetic\\n',{mode:0o600});`);
    await writeFile(join(directory, 'scripts/check-cloud.mjs'), `if(!process.argv.includes('--backend-only'))process.exit(1);`);
    const cli = join(directory, 'supabase-stub.mjs'), log = join(directory, 'commands.jsonl');
    await writeFile(cli, `#!/usr/bin/env node
import {appendFile,mkdir,readFile,stat,writeFile} from 'node:fs/promises';
const args=process.argv.slice(2);
await appendFile(process.env.CLOUD_COMMAND_LOG,JSON.stringify(args)+'\\n');
if(args[0]==='link') {await mkdir('supabase/.temp',{recursive:true});await writeFile('supabase/.temp/project-ref',process.env.CLOUD_FOREIGN_PROJECT?'other-project':args[args.indexOf('--project-ref')+1]);}
if(args[0]==='secrets') {const file=args[args.indexOf('--env-file')+1];if(((await stat(file)).mode&0o777)!==0o600)process.exit(2);if(!(await readFile(file,'utf8')).startsWith('GEMINI_API_KEY='))process.exit(3);}
`, { mode: 0o700 });
    const run = execute('sh', [join(directory, 'scripts/deploy-supabase.sh'), mode === 'foreign-project' ? 'apply' : mode], { cwd: directory, env: { ...process.env, SUPABASE_CLI: cli, CLOUD_COMMAND_LOG: log, CLOUD_FOREIGN_PROJECT: mode === 'foreign-project' ? '1' : '' } });
    if (mode === 'foreign-project') await assert.rejects(run); else await run;
    const commands = (await readFile(log, 'utf8')).trim().split('\n').map(line => JSON.parse(line));
    assert.equal(commands[0][0], 'link'); assert.ok(commands[0].includes(project));
    const args = commands.flat();
    for (const forbidden of ['reset', '--include-seed', '--include-all', '--prune', '--no-verify-jwt', '--debug']) assert.ok(!args.includes(forbidden));
    if (mode === 'foreign-project') { assert.equal(commands.length, 1); continue; }
    assert.deepEqual(commands[1], ['db', 'push', '--linked', '--dry-run', '--skip-vault']);
    if (mode === 'plan') assert.equal(commands.length, 2);
    else {
      assert.deepEqual(commands[2], ['db', 'push', '--linked', '--skip-vault']);
      assert.equal(commands[3][0], 'secrets');
      const secretPath = commands[3][commands[3].indexOf('--env-file') + 1];
      await assert.rejects(stat(secretPath));
      assert.deepEqual(commands.slice(4).map(command => command[2]), ['ledger', 'ios-data', 'export-data', 'receipt-scan']);
    }
  }
});

test('server secret preparation validates model and excludes client/admin values', async context => {
  const directory = await workspace(context);
  const source = join(directory, '.env'), destination = join(directory, 'secrets'), mock = join(directory, 'model.mjs');
  await writeFile(mock, `globalThis.fetch=async()=>Response.json({supportedGenerationMethods:['generateContent']});`);
  await writeFile(source, 'GEMINI_API_KEY=synthetic-api-key\nGEMINI_MODEL=gemini-3.5-flash-lite\nSUPABASE_SERVICE_ROLE_KEY=synthetic\nVITE_SUPABASE_URL=https://not-uploaded.invalid\nLOCAL_RECEIPT_SCAN=1\n');
  const script = new URL('../../scripts/prepare-cloud-secrets.mjs', import.meta.url).pathname;
  const result = await execute(process.execPath, ['--import', mock, script, source, destination, 'https://app.example.invalid']);
  assert.ok(!result.stdout.includes('synthetic-api-key'));
  const contents = await readFile(destination, 'utf8');
  assert.ok(contents.includes('GEMINI_API_KEY=synthetic-api-key'));
  assert.ok(contents.includes('ALLOWED_ORIGINS=https://app.example.invalid,http://127.0.0.1:5173,http://localhost:5173'));
  assert.ok(!contents.includes('SUPABASE_')); assert.ok(!contents.includes('LOCAL_RECEIPT_SCAN'));
  assert.equal((await stat(destination)).mode & 0o777, 0o600);
  await assert.rejects(execute(process.execPath, ['--import', mock, script, source, destination, 'http://remote.invalid']));
  await writeFile(mock, `globalThis.fetch=async()=>new Response('',{status:403});`);
  await assert.rejects(execute(process.execPath, ['--import', mock, script, source, destination, 'https://app.example.invalid']));
});

test('readiness requires protected schemas/functions; backend-only never pretends OAuth is verified', async context => {
  const directory = await workspace(context), mock = join(directory, 'cloud.mjs');
  await writeFile(mock, `globalThis.fetch=async input=>{const path=new URL(input).pathname;if(path.endsWith('/settings'))return Response.json({external:{google:process.env.CLOUD_GOOGLE_ENABLED==='true',apple:false}});if(path.startsWith('/rest/v1/'))return Response.json({code:'42501'},{status:401});return Response.json({code:process.env.CLOUD_FUNCTION_STATUS==='404'?'NOT_FOUND':'UNAUTHORIZED'},{status:Number(process.env.CLOUD_FUNCTION_STATUS||401)});};`);
  const script = new URL('../../scripts/check-cloud.mjs', import.meta.url).pathname;
  const args = ['--experimental-strip-types', '--import', mock, script];
  await execute(process.execPath, [...args, '--backend-only']);
  await assert.rejects(execute(process.execPath, args));
  const googleOnly = await execute(process.execPath, args, { env: { ...process.env, CLOUD_GOOGLE_ENABLED: 'true' } });
  assert.ok(!googleOnly.stdout.includes('Login apple'));
  for (const status of ['404', '200']) await assert.rejects(execute(process.execPath, [...args, '--backend-only'], { env: { ...process.env, CLOUD_FUNCTION_STATUS: status } }));
});
