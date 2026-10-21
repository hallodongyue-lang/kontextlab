begin;
select set_config('test.kl_user',gen_random_uuid()::text,true),set_config('test.kl_other',gen_random_uuid()::text,true);
insert into auth.users(id,email,is_anonymous) values(current_setting('test.kl_user')::uuid,'research-test-'||current_setting('test.kl_user')||'@example.invalid',false),(current_setting('test.kl_other')::uuid,'research-test-'||current_setting('test.kl_other')||'@example.invalid',false);
select set_config('request.jwt.claim.sub',current_setting('test.kl_user'),true);
set local role authenticated;
insert into public.kl_experiments(user_id,protocol,item,relation,initial,final,reason,consent) values(auth.uid(),'context-1.0','toll','friends','uncertain','praise','Disposable test reasoning',false);
do $$declare rejected boolean:=false;begin
 if jsonb_array_length(public.kl_research_data()->'experiments')<>0 then raise exception 'private record leaked';end if;
 update public.kl_experiments set consent=true where user_id=auth.uid();
 if jsonb_array_length(public.kl_research_data()->'experiments')<>1 then raise exception 'opt-in missing';end if;
 update public.kl_experiments set withdrawn_at=now() where user_id=auth.uid();
 if jsonb_array_length(public.kl_research_data()->'experiments')<>0 then raise exception 'withdrawal not applied';end if;
 begin insert into public.kl_experiments(user_id,protocol,item,relation,initial,final,reason) values(current_setting('test.kl_other')::uuid,'context-1.0','genie','friends','uncertain','praise','Forged owner should fail');exception when insufficient_privilege then rejected:=true;end;
 if not rejected then raise exception 'forged ownership accepted';end if;
end$$;
select set_config('request.jwt.claim.sub',current_setting('test.kl_other'),true);
do $$declare n int;begin
 if exists(select 1 from public.kl_experiments) then raise exception 'other records visible';end if;
 delete from public.kl_experiments where user_id=current_setting('test.kl_user')::uuid;
 get diagnostics n=row_count;if n<>0 then raise exception 'cross-account deletion';end if;
end$$;
select set_config('request.jwt.claim.sub',current_setting('test.kl_user'),true);
delete from public.kl_experiments where user_id=auth.uid();
do $$begin if exists(select 1 from public.kl_experiments) then raise exception 'owner deletion failed';end if;end$$;
reset role;
select 'PASS: private by default, explicit opt-in, withdrawal, forged owner denied, other account read/delete denied, owner delete works' as result;
rollback;
