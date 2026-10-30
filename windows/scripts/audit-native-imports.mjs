import { readFile, readdir } from 'node:fs/promises';
import { basename, join, resolve } from 'node:path';

const root=resolve(process.argv[2]);
const binaries=[];
async function walk(path){for(const entry of await readdir(path,{withFileTypes:true})){const full=join(path,entry.name);if(entry.isDirectory())await walk(full);else if(/\.(?:dll|exe)$/i.test(entry.name))binaries.push(full);}}
await walk(root);
const names=new Set(binaries.map(p=>basename(p).toLowerCase()));
const missing=new Map();
for(const file of binaries){
  const b=await readFile(file);if(b.length<64||b.readUInt16LE(0)!==0x5a4d)continue;
  const pe=b.readUInt32LE(0x3c);if(pe+24>b.length||b.readUInt32LE(pe)!==0x4550)throw new Error('Invalid PE header');
  const optional=pe+24;const magic=b.readUInt16LE(optional);if(![0x10b,0x20b].includes(magic))continue;
  const directories=optional+(magic===0x20b?112:96);const importRva=b.readUInt32LE(directories+8);if(!importRva)continue;
  const sectionCount=b.readUInt16LE(pe+6),sectionStart=optional+b.readUInt16LE(pe+20);
  function offset(rva){
    if(rva<b.readUInt32LE(optional+60))return rva;
    for(let i=0;i<sectionCount;i++){
      const s=sectionStart+i*40;const start=b.readUInt32LE(s+12);const size=Math.max(b.readUInt32LE(s+8),b.readUInt32LE(s+16));
      if(rva>=start&&rva<start+size){const raw=b.readUInt32LE(s+20)+rva-start;if(raw>=b.length)throw new Error('PE RVA outside file');return raw;}
    }
    throw new Error('Unmapped PE RVA');
  }
  for(let descriptor=offset(importRva);descriptor+20<=b.length;descriptor+=20){
    const nameRva=b.readUInt32LE(descriptor+12);if(!nameRva)break;
    const start=offset(nameRva),end=b.indexOf(0,start);if(end<start||end-start>256)throw new Error('Invalid PE import name');
    const dependency=b.toString('ascii',start,end).toLowerCase();
    if(names.has(dependency)||dependency.startsWith('api-ms-')||dependency.startsWith('ext-ms-'))continue;
    if(/^(?:msvcp|vcruntime|concrt|vcomp|libomp|cudart|cublas|cudnn|onnxruntime|sherpa)/.test(dependency)){
      const parents=missing.get(dependency)??new Set();parents.add(basename(file));missing.set(dependency,parents);
    }
  }
}
if(missing.size){for(const [dependency,parents] of missing)console.error(`Missing redistributable ${dependency}: ${[...parents].join(', ')}`);process.exitCode=1;}
else console.log(`PASS: ${binaries.length} PE binaries have no missing imported C++/inference runtime DLLs in the package.`);
