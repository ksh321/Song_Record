import test,{afterEach} from 'node:test';
import assert from 'node:assert/strict';
import {receiptFrom,commandFor,restrictedStatus,statusMessage,api,Failure} from './main.js';
const originalFetch=globalThis.fetch;afterEach(()=>{globalThis.fetch=originalFetch;});
const prep='11111111-1111-4111-8111-111111111111',owner='22222222-2222-4222-8222-222222222222';
function prepared(){return {preparation_id:prep,reauth_proof:owner,user_id:owner,device_id:owner,access_token:'sr_a_'+'a'.repeat(43),status_token:'s'.repeat(43),base_revision:1,prepare_expires_at:'2026-10-12T12:00:00Z'};}
test('protected receipt excludes general session and preserves one operation for an explicit intent',()=>{
 const r=receiptFrom(prepared());assert.equal(r.access_token,undefined);assert.equal(r.device_id,undefined);assert.throws(()=>commandFor(r,false));
 assert.deepEqual(commandFor(r,true),{preparation_id:prep,reauth_proof:owner,base_revision:1,scope:'ALL_ACCOUNT_DATA',confirmed:true});
 assert.equal(JSON.parse(JSON.stringify(r)).operation,r.operation);assert.notEqual(receiptFrom(prepared()).operation,r.operation);
});
test('malformed preparation cannot enable protected submission',()=>{
 for(const [key,value] of [['user_id','email@example.invalid'],['base_revision',1.5],['status_token','short'],['access_token','unsigned'],['preparation_id','bad'],['prepare_expires_at','unknown']])assert.throws(()=>receiptFrom({...prepared(),[key]:value}));
});
test('restricted status never accepts account identifiers or an unknown completion state',()=>{
 const status={status:'ACCEPTED',retrying:false,accepted_at:'2026-10-12T00:00:00Z',service_deleted_at:null,backup_purge_due_at:'2026-10-19T00:00:00Z',completed_at:null,expires_at:'2026-11-11T00:00:00Z'};
 assert.deepEqual(restrictedStatus(status),status);assert.throws(()=>restrictedStatus({...status,email:'private'}));assert.throws(()=>restrictedStatus({...status,status:'FINISHED_BY_TIMEOUT'}));assert.throws(()=>restrictedStatus({...status,retrying:1}));
});
test('status uses same-origin dedicated header, no cookies, no redirect and no token in URL',async()=>{
 let observed;globalThis.fetch=async(path,options)=>{observed={path,options};return new Response('{"status":"PREPARED"}');};
 await api(`/v1/account/deletion-status/${prep}`,{statusProof:'s'.repeat(43)});
 assert.equal(observed.path,`/v1/account/deletion-status/${prep}`);assert.equal(observed.options.headers.Authorization,undefined);assert.equal(observed.options.headers['X-Deletion-Status-Token'],'s'.repeat(43));assert.equal(observed.options.credentials,'omit');assert.equal(observed.options.redirect,'error');
 await assert.rejects(api('https://attacker.invalid/steal'),/Invalid same-origin/);
});
test('failure bodies and oversized responses do not become displayed account data',async()=>{
 globalThis.fetch=async()=>new Response('{"sensitive":"do not display"}',{status:429});await assert.rejects(api('/v1/account/web/configuration'),e=>e instanceof Failure&&e.status===429&&!e.message.includes('sensitive'));
 globalThis.fetch=async()=>new Response(new Uint8Array(65537));await assert.rejects(api('/v1/account/web/configuration'),/Response too large/);
});

test('backup delay and retry remain incomplete; only verified service and backup completion is displayed',()=>{
 const waiting={status:'BACKUP_CLEANUP',retrying:true,accepted_at:'2026-10-01T00:00:00Z',service_deleted_at:'2026-10-02T00:00:00Z',backup_purge_due_at:'2026-10-08T00:00:00Z',completed_at:null,expires_at:'2026-10-31T00:00:00Z'};
 const message=statusMessage(waiting,Date.parse('2026-10-13T00:00:00Z'));
 assert.match(message,/재시도/);assert.match(message,/기한을 초과/);assert.match(message,/아직 전체 삭제 완료가 아닙니다/);assert.equal(waiting.status,'BACKUP_CLEANUP');
 const done={...waiting,status:'COMPLETED',retrying:false,completed_at:'2026-10-03T00:00:00Z'};
 assert.match(statusMessage(done),/운영 백업 정리가 확인/);
 for(const bad of [{...done,completed_at:null},{...done,service_deleted_at:null},{...done,retrying:true},{...done,completed_at:'2026-09-01T00:00:00Z'},{...waiting,expires_at:'invalid'},{...waiting,backup_purge_due_at:'2026-10-09T00:00:00Z'}])assert.throws(()=>restrictedStatus(bad));
 assert.match(statusMessage({status:'PREPARED',retrying:false,expires_at:'2026-10-01T00:10:00Z'}),/접수 전/);
});
