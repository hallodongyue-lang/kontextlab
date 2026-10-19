import { createClient } from 'npm:@supabase/supabase-js@2.102.0';
const origins=new Set(['https://hallodongyue-lang.github.io','http://localhost:4173','http://127.0.0.1:4173']);
Deno.serve(async(req:Request)=>{
 const origin=req.headers.get('origin')||'';
 const cors={'Access-Control-Allow-Origin':origins.has(origin)?origin:'https://hallodongyue-lang.github.io','Access-Control-Allow-Headers':'apikey, authorization, content-type, x-client-info','Access-Control-Allow-Methods':'POST, OPTIONS','Vary':'Origin'};
 const json=(body:unknown,status=200)=>new Response(JSON.stringify(body),{status,headers:{...cors,'Content-Type':'application/json','Cache-Control':'no-store'}});
 if(origin&&!origins.has(origin))return json({error:'origin_not_allowed'},403);
 if(req.method==='OPTIONS')return new Response('ok',{headers:cors});
 if(req.method!=='POST')return json({error:'method_not_allowed'},405);
 try{
  const raw=await req.text();if(raw.length>2000)return json({error:'invalid_input'},400);
  const body=JSON.parse(raw);const email=typeof body.email==='string'?body.email.trim().toLowerCase():'';const password=body.password;
  if(!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)||email.length>254||typeof password!=='string'||password.length<8||password.length>72)return json({error:'invalid_input'},400);
  const url=Deno.env.get('SUPABASE_URL')!,secret=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  if(!url||!secret)return json({error:'registration_unavailable'},503);
  const admin=createClient(url,secret,{auth:{persistSession:false,autoRefreshToken:false}});
  const ip=req.headers.get('x-forwarded-for')?.split(',')[0]?.trim()||'unknown';
  const key=await crypto.subtle.importKey('raw',new TextEncoder().encode(secret),{name:'HMAC',hash:'SHA-256'},false,['sign']);
  const hash=async(s:string)=>Array.from(new Uint8Array(await crypto.subtle.sign('HMAC',key,new TextEncoder().encode(s)))).map(n=>n.toString(16).padStart(2,'0')).join('');
  const {error:gateError}=await admin.rpc('kl_register_gate',{p_ip:await hash('ip:'+ip),p_email:await hash('email:'+email)});
  if(gateError)return json({error:'registration_rate_limit'},429);
  // Explicit no-email-confirmation registration requested by the site owner.
  // No mailbox ownership or verified identity is claimed by the application.
  const {error}=await admin.auth.admin.createUser({email,password,email_confirm:true});
  if(error)return json({error:'registration_failed'},400);
  return json({ok:true});
 }catch{return json({error:'registration_unavailable'},503)}
});
