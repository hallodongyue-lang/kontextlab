create table if not exists kl_private.registration_rate(key_hash text not null,window_date date not null default current_date,n int not null default 1,primary key(key_hash,window_date));
alter table kl_private.registration_rate enable row level security;
revoke all on kl_private.registration_rate from public,anon,authenticated;
create or replace function kl_private.registration_gate(p_ip text,p_email text) returns void language plpgsql security definer set search_path='' as $$
declare ip_n int;email_n int;begin
 if p_ip !~ '^[0-9a-f]{64}$' or p_email !~ '^[0-9a-f]{64}$' then raise exception 'invalid_hash';end if;
 insert into kl_private.registration_rate(key_hash) values('ip:'||p_ip) on conflict(key_hash,window_date) do update set n=kl_private.registration_rate.n+1 returning n into ip_n;
 insert into kl_private.registration_rate(key_hash) values('email:'||p_email) on conflict(key_hash,window_date) do update set n=kl_private.registration_rate.n+1 returning n into email_n;
 if ip_n>10 or email_n>3 then raise exception 'registration_rate_limit';end if;
 delete from kl_private.registration_rate where window_date<current_date-2;
end;$$;
revoke all on function kl_private.registration_gate(text,text) from public,anon,authenticated;
grant usage on schema kl_private to service_role;
grant execute on function kl_private.registration_gate(text,text) to service_role;
create or replace function public.kl_register_gate(p_ip text,p_email text) returns void language sql security invoker set search_path='' as $$select kl_private.registration_gate(p_ip,p_email);$$;
revoke all on function public.kl_register_gate(text,text) from public,anon,authenticated;
grant execute on function public.kl_register_gate(text,text) to service_role;
create or replace function kl_private.require_user() returns uuid language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid();begin
 if uid is null or not exists(select 1 from auth.users where id=uid and is_anonymous is not true and (banned_until is null or banned_until<now())) then raise exception 'login_required';end if;return uid;end;$$;
revoke all on function kl_private.require_user() from public,anon;
grant execute on function kl_private.require_user() to authenticated;
