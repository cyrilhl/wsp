const {test} = require('node:test');
const assert = require('node:assert/strict');
const vm = require('node:vm');
const fs = require('node:fs');
const bridge = fs.readFileSync('web/ocr_bridge.js','utf8');
function bridgeContext(createWorker, timeout = setTimeout, extra = {}) {
  const context = {window:{},document:{baseURI:'http://localhost/'},URL,Error,Promise,setTimeout:timeout,clearTimeout,Tesseract:{createWorker},...extra};
  vm.runInNewContext(bridge,context);
  return context.window._extractText;
}
function word(text, x, y, width, height) {
  return {text, bbox:{x0:x,y0:y,x1:x+width,y1:y+height}};
}
function localizedOcr(words, results = ['12.5'], enhanced = false) {
  const draws = [], parameters = [], inputs = [];
  const ctx = {fillRect(){},drawImage(...args){draws.push(args.slice(1));},
    getImageData(){return {data:new Uint8ClampedArray(4)};},putImageData(){}};
  let calls = 0;
  const extract = bridgeContext(async () => ({
    loadLanguage:async()=>{},initialize:async()=>{},terminate:async()=>{},
    setParameters:async p=>parameters.push(p),
    recognize:async input=>{inputs.push(input);return {data: calls++ === 0 ? {words,text:'background'} : {text:results.shift()}};},
  }), setTimeout, {
    Image:class {naturalWidth=600;naturalHeight=300;async decode(){}},
    document:{baseURI:'http://localhost/',createElement:()=>({getContext:()=>ctx,toDataURL:()=> 'cropped'})},
  });
  return {result:extract('photo',{args:{meter_enhance:enhanced}}),draws,parameters,inputs};
}
test('largest numeric row excludes small labels and preserves detached punctuation', async () => {
  const run = localizedOcr([word('MODEL',10,10,150,60),word('2026',400,10,40,12),
    word('12.5',150,100,160,60),word('-',115,130,20,5),word('.',312,155,5,5)],['-12.5']);
  assert.equal(await run.result,'-12.5');
  assert.equal(run.parameters[0].tessedit_char_whitelist,'');
  assert.equal(run.parameters[0].tessedit_pageseg_mode,'11');
  assert.equal(run.parameters[1].tessedit_pageseg_mode,'13');
  const [left,top,width,height] = run.draws[0];
  assert.ok(left <= 115 && left + width >= 317);
  assert.ok(top > 22 && top + height >= 160);
  assert.deepEqual(run.inputs,['photo','cropped']);
});
test('similarly large separate readings require review', async () => {
  const run = localizedOcr([word('12.5',100,40,120,60),word('18.2',100,170,120,55)]);
  assert.equal(await run.result,'');
  assert.equal(run.inputs.length,1);
});
test('localization tolerates a minus misread as multiple dash glyphs', async () => {
  const run = localizedOcr([word('—-8.2',100,100,200,68),word('2026',100,10,40,12),
    word('100%',100,210,40,12)],['-8.2']);
  assert.equal(await run.result,'-8.2');
  assert.equal(run.draws.length,1);
});
test('a detected minus cannot silently disappear from the final reading', async () => {
  const run = localizedOcr([word('-8.2',100,100,200,68)],['8.2','8.2'],true);
  assert.equal(await run.result,'');
});
test('separated side-by-side readings require review', async () => {
  const run = localizedOcr([word('12.5',20,100,120,60),word('18.2',350,100,120,60)]);
  assert.equal(await run.result,'');
});
test('adjacent digit groups stay in one crop without concatenating OCR tokens', async () => {
  const run = localizedOcr([word('12',100,100,60,60),word('5',180,100,30,60)],['12 5']);
  assert.equal(await run.result,'12 5');
  assert.equal(run.draws.length,1);
  assert.ok(run.draws[0][0] + run.draws[0][2] >= 210);
});
test('missing localization falls back to the full viewfinder', async () => {
  const run = localizedOcr([],['8.2']);
  assert.equal(await run.result,'8.2');
  assert.deepEqual(run.inputs,['photo','photo']);
});
test('conflicting original and enhanced readings require review', async () => {
  const run = localizedOcr([word('12.5',100,100,120,60)],['12.5','125'],true);
  assert.equal(await run.result,'');
});
test('a valid original survives an unreadable enhanced variant', async () => {
  const run = localizedOcr([word('12.5',100,100,120,60)],['12.5',''],true);
  assert.equal(await run.result,'12.5');
});
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
