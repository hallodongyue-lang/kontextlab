const vm=require('vm'),fs=require('fs'),assert=require('assert');
const stub={addEventListener(){}};const ctx={console,document:{querySelector:()=>stub,addEventListener(){}},window:{addEventListener(){}},localStorage:{getItem:()=>null},location:{hash:'#library'},setTimeout,clearTimeout,TextDecoder,Uint8Array};vm.createContext(ctx);vm.runInContext(fs.readFileSync('src/app.js','utf8').replace(/init\(\);\s*$/,''),ctx);let run=s=>vm.runInContext(s,ctx);
assert(run('Object.values(DICT).every(v=>v.length===3&&v.every(x=>typeof x==="string"&&x.length))'));
for(const [n,stars]of [[0,0],[1,1],[4,1],[5,2],[15,3],[30,4],[60,5],[99,5]])assert.equal(run(`level(${n}).stars`),stars);
assert.equal(run('level(3).percent'),50);assert.equal(run('level(60).percent'),100);
assert.equal(run('leading({votes:5,ballots:{normal:3,irony:1,reject:1}}).ratio'),.6);assert.equal(run('leading({votes:0,ballots:{}}).ratio'),0);
assert.equal(run('esc("<img onerror=alert(1)>")'),'&lt;img onerror=alert(1)&gt;');assert(run('DICT.authNote[0].includes("不发送验证邮件")'));
for(const l of ['zh','en','de']){run(`lang='${l}'`);assert(run('TAGS.every(k=>tag(k)!==undefined)'))}
const bundle=fs.readFileSync('index.html','utf8');assert(bundle.includes('functions/v1/kl-register'));assert(!bundle.includes('service_role'));assert(bundle.includes('KL_LEGACY'));console.log('PASS: three-language dictionaries, all tag labels, star thresholds/progress, 60% denominator, zero votes, escaping, no-mail signup, no service-role secret in browser, preserved V1 lab.');
