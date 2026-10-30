import assert from 'node:assert/strict';
import { readdir, readFile, lstat } from 'node:fs/promises';
import { resolve, join, relative, basename } from 'node:path';

const root=resolve(process.argv[2]??'dist');
const files=[];
async function visit(directory){
  for(const name of await readdir(directory)){
    const file=join(directory,name);const info=await lstat(file);assert.ok(!info.isSymbolicLink(),'Package contains a link');
    if(info.isDirectory()){
      assert.ok(!['LocalMinutes.Data','.agent-local','models','Models.Downloaded','SyncIncoming','SyncOutgoing','rollback','identity','test-data'].includes(name),`Private/generated data directory: ${name}`);
      await visit(file);
    }else{
      assert.ok(!/\.(?:gguf|onnx|sqlite|sqlite3|db|caf|wav|m4a|pfx|pem|key|p12|pdb)$/i.test(name),`Private/model/debug file in package: ${name}`);
      assert.ok(!['sync.dat','device.json','records.jsonl','model-selection.json'].includes(name),'Private state in package');
      files.push(relative(root,file).replaceAll('\\','/'));
    }
  }
}
await visit(root);
for(const expected of ['LocalMinutes.exe','LocalMinutes.runtimeconfig.json','runtimes/llama/llama-completion.exe','runtimes/llama/llama-tokenize.exe','runtimes/llama/llama.dll'])assert.ok(files.includes(expected),`Missing ${expected}`);
assert.ok(files.some(p=>p.endsWith('sherpa-onnx-c-api.dll')),'Speech runtime missing');
assert.ok(files.some(p=>p.endsWith('onnxruntime.dll')),'ONNX runtime missing');
assert.ok(files.includes('coreclr.dll'),'Self-contained .NET runtime missing');
assert.ok(files.includes('vcruntime140.dll')&&files.includes('msvcp140.dll'),'App-local C++ runtime missing');
if(basename(root).includes('-cuda-')){
  assert.ok(files.includes('runtimes/llama/ggml-cuda.dll')&&files.includes('runtimes/llama/cudart64_13.dll')&&files.includes('runtimes/llama/cublas64_13.dll'),'CUDA runtime incomplete');
  assert.ok(files.includes('licenses/NVIDIA-CUDA-EULA.html'),'CUDA terms missing');
}else assert.ok(!files.includes('runtimes/llama/ggml-cuda.dll'),'CUDA libraries leaked into CPU build');
assert.ok(!files.some(p=>/llama-server|rpc-server|appsettings|launchSettings/i.test(p)),'Unexpected server/configuration payload');
const config=JSON.parse(await readFile(join(root,'LocalMinutes.runtimeconfig.json'),'utf8'));
assert.ok(config.runtimeOptions.includedFrameworks?.some(f=>f.name==='Microsoft.WindowsDesktop.App'),'Desktop framework is not bundled');
assert.ok(files.some(p=>p.startsWith('licenses/')),'Dependency notices missing');
for(const license of ['Makaretu.Dns.Multicast-MIT.txt','Makaretu.Dns-MIT.txt','IPNetwork2-BSD.txt','Tmds.LibC-MIT.txt'])assert.ok(files.includes('licenses/'+license),`Missing discovery dependency license: ${license}`);
console.log(`PASS: ${basename(root)} contains ${files.length} application/runtime/license files, no models or meeting data.`);
