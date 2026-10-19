begin;
select set_config('test.kl_user',gen_random_uuid()::text,true),set_config('test.kl_other',gen_random_uuid()::text,true);
insert into auth.users(id,email,is_anonymous) values(current_setting('test.kl_user')::uuid,'kl-guide-'||current_setting('test.kl_user')||'@example.invalid',false),(current_setting('test.kl_other')::uuid,'kl-guide-'||current_setting('test.kl_other')||'@example.invalid',false);
select set_config('request.jwt.claim.sub',current_setting('test.kl_user'),true);
set local role authenticated;
do $$
declare changed int;rejected boolean:=false;begin
 if (select onboarding_step from public.kl_profiles where id=auth.uid())<>0 then raise exception 'new profile must start at zero';end if;
 update public.kl_profiles set onboarding_step=2 where id=auth.uid();
 if (select onboarding_step from public.kl_profiles where id=auth.uid())<>2 then raise exception 'own progress update failed';end if;
 update public.kl_profiles set onboarding_step=5 where id=current_setting('test.kl_other')::uuid;
 get diagnostics changed=row_count;if changed<>0 then raise exception 'other user progress changed';end if;
 begin update public.kl_profiles set onboarding_step=6 where id=auth.uid();exception when check_violation then rejected:=true;end;
 if not rejected then raise exception 'out of range progress accepted';end if;
 update public.kl_profiles set onboarding_step=5,onboarding_completed_at=now() where id=auth.uid();
 if not exists(select 1 from public.kl_profiles where id=auth.uid() and onboarding_step=5 and onboarding_completed_at is not null) then raise exception 'completion not persisted';end if;
end;$$;
reset role;
select 'PASS: new account starts at 0, own progress/completion persist, other account unchanged, invalid stage rejected' as result;
rollback;
