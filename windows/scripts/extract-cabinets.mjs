import {readFile,writeFile,mkdir} from 'node:fs/promises';
import {resolve,join} from 'node:path';

// Called only after prepare-vc-runtime verifies the exact Microsoft-signed executable and SHA-256.
const data=await readFile(resolve(process.argv[2]));const directory=resolve(process.argv[3]);await mkdir(directory,{recursive:true});
let cursor=0,index=0;
while((cursor=data.indexOf(Buffer.from('MSCF'),cursor))>=0){
  if(cursor+36>data.length)break;const size=data.readUInt32LE(cursor+8);
  if(size<36||cursor+size>data.length||data[cursor+24]!==3||data[cursor+25]!==1||!data.readUInt16LE(cursor+26)){cursor+=4;continue;}
  const cabinet=data.subarray(cursor,cursor+size);let position=cabinet.readUInt32LE(16);
  for(let file=0;file<cabinet.readUInt16LE(28);file++){
    position+=16;const end=cabinet.indexOf(0,position);if(end<position)throw new Error('Invalid cabinet filename');
    const name=cabinet.toString('utf8',position,end);if(!name||/[\\/:]/.test(name)||name==='.'||name==='..')throw new Error('Unsafe cabinet path');position=end+1;
  }
  await writeFile(join(directory,`container-${index++}.cab`),cabinet);cursor+=size;
}
if(index!==2)throw new Error('Unexpected pinned redistributable cabinet structure');
