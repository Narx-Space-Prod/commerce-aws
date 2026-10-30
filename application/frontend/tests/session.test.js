import {test} from 'node:test';import assert from 'node:assert/strict';import {session,signedCookie} from '../src/session.js';
const secret='s'.repeat(40);
test('signed session remains stable',()=>{const s=session('',secret);const c=signedCookie(s.id,secret,true);assert.match(c,/HttpOnly/);assert.match(c,/Secure/);assert.deepEqual(session(c,secret),{id:s.id,fresh:false});});
test('tampered signature rejected',()=>{const s=session('',secret);assert.notEqual(session(signedCookie(s.id,'different-secret',false),secret).id,s.id);});
