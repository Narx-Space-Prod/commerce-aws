import {test} from 'node:test';
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {createServer} from 'node:net';
import {once} from 'node:events';
import {readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';

async function unusedPort(){
  const server=createServer();
  server.listen(0,'127.0.0.1');
  await once(server,'listening');
  const {port}=server.address();
  await new Promise((resolve,reject)=>server.close(error=>error?reject(error):resolve()));
  return port;
}

test('HTML uses content-fingerprinted assets with immutable caching',async t=>{
  const port=await unusedPort();
  const child=spawn(process.execPath,['src/server.js'],{
    cwd:process.cwd(),
    env:{...process.env,PORT:String(port),SESSION_SECRET:'test-session-secret-0123456789abcdef'},
    stdio:'ignore'
  });
  t.after(()=>{if(child.exitCode===null){child.kill('SIGTERM');}});

  const origin=`http://127.0.0.1:${port}`;
  let page;
  for(let attempt=0;attempt<40;attempt++){
    try{page=await fetch(origin);break;}catch{await new Promise(resolve=>setTimeout(resolve,50));}
  }
  assert.ok(page,'frontend server did not start');
  assert.equal(page.status,200);
  assert.equal(page.headers.get('cache-control'),'no-store');
  const html=await page.text();
  const cssPath=html.match(/href="(\/style\.[a-f0-9]{16}\.css)"/)?.[1];
  const jsPath=html.match(/src="(\/app\.[a-f0-9]{16}\.js)"/)?.[1];
  assert.ok(cssPath,'stylesheet URL must include its content fingerprint');
  assert.ok(jsPath,'script URL must include its content fingerprint');
  for(const [path,file] of [[cssPath,'style.css'],[jsPath,'app.js']]){
    const content=await readFile(new URL('../public/'+file,import.meta.url));
    const hash=createHash('sha256').update(content).digest('hex').slice(0,16);
    assert.ok(path.includes(hash),'asset URL must match its actual contents');
    const response=await fetch(origin+path);
    assert.deepEqual(Buffer.from(await response.arrayBuffer()),content);
  }
  assert.equal((await fetch(origin+'/style.0000000000000000.css')).status,404);

  for(const [path,type] of [[cssPath,'text/css'],[jsPath,'text/javascript']]){
    const response=await fetch(origin+path);
    assert.equal(response.status,200);
    assert.match(response.headers.get('content-type'),new RegExp(type));
    assert.equal(response.headers.get('cache-control'),'public, max-age=31536000, immutable');
    assert.equal(response.headers.get('cloudflare-cdn-cache-control'),'public, max-age=31536000, immutable');
  }
});
