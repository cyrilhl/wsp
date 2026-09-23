const {test} = require('node:test');
const assert = require('node:assert/strict');
const vm = require('node:vm');
const fs = require('node:fs');
const bridge = fs.readFileSync('web/ocr_bridge.js','utf8');
function bridgeContext(createWorker, timeout = setTimeout) {
  const context = {window:{},document:{baseURI:'http://localhost/'},URL,Error,Promise,setTimeout:timeout,clearTimeout,Tesseract:{createWorker}};
  vm.runInNewContext(bridge,context);
  return context.window._extractText;
}
test('OCR reuses one worker and serializes recognition', async () => {
  let created=0,active=0,maximum=0;
  const extract = bridgeContext(async () => {
    created++;
    return {loadLanguage:async()=>{},initialize:async()=>{},setParameters:async()=>{},
      recognize:async source=>{active++;maximum=Math.max(maximum,active);await new Promise(r=>setTimeout(r,5));active--;return {data:{text:source}};},terminate:async()=>{}};
  });
  assert.deepEqual(await Promise.all([extract('12',{args:{}}),extract('34',{args:{}})]),['12','34']);
  assert.equal(created,1);assert.equal(maximum,1);
});
test('OCR worker failure resets engine and allows retry', async () => {
  let created=0,terminated=0;
  const extract=bridgeContext(async () => {
    const attempt=++created;
    return {loadLanguage:async()=>{},initialize:async()=>{},setParameters:async()=>{},recognize:async()=>{
      if(attempt===1)throw Error('worker failed');return {data:{text:'12.5'}};
    },terminate:async()=>{terminated++;}};
  });
  await assert.rejects(extract('data',{args:{}}),/worker failed/);
  assert.equal(await extract('data',{args:{}}),'12.5');assert.equal(terminated,1);assert.equal(created,2);
});
test('failed offline install preserves previous complete cache', async () => {
  const source=fs.readFileSync('build/web/meter-sw.js','utf8');
  const handlers={}; const stores=new Map([['fieldnote-previous',new Map([['sentinel','ready']])]]);
  let newName;
  const caches={open:async name=>{newName=name;stores.set(name,new Map());return {addAll:async()=>{throw Error('network interrupted');},put:async()=>{}};},delete:async name=>stores.delete(name)};
  vm.runInNewContext(source,{self:{registration:{scope:'http://localhost/'},addEventListener:(name,cb)=>handlers[name]=cb},caches,URL,Request,Response,Promise});
  let installation;handlers.install({waitUntil:p=>installation=p});
  await assert.rejects(installation,/network interrupted/);
  assert.equal(stores.has(newName),false);assert.equal(stores.get('fieldnote-previous').get('sentinel'),'ready');
});

test('OCR timeout terminates the worker and next job can succeed', async () => {
  let created = 0, terminated = 0;
  const extract = bridgeContext(async () => {
    const attempt = ++created;
    return {loadLanguage:async()=>{},initialize:async()=>{},setParameters:async()=>{},
      recognize:async()=> attempt === 1 ? new Promise(()=>{}) : {data:{text:'8.2'}},
      terminate:async()=>{terminated++;}};
  }, callback => setTimeout(callback, 10));
  await assert.rejects(extract('data',{args:{}}), /timed out/);
  assert.equal(terminated, 1);
  assert.equal(await extract('data',{args:{}}), '8.2');
});
