create schema if not exists kl_private;
revoke all on schema kl_private from public;
grant usage on schema kl_private to authenticated;
create table public.kl_profiles (
 id uuid primary key references auth.users(id) on delete cascade,
 display_name text not null default 'Researcher' check(char_length(display_name) between 1 and 60),
 bio text not null default '' check(char_length(bio)<=600),
 created_at timestamptz not null default now()
);
create table public.kl_samples (
 id uuid primary key default gen_random_uuid(), author_id uuid references public.kl_profiles(id),
 text text not null check(char_length(text) between 3 and 2000),
 translation text not null default '' check(char_length(translation)<=2000),
 context text not null check(char_length(context) between 5 and 3000),
 language text not null default 'de' check(language in ('de','en','zh')),
 proposed_tag text not null check(proposed_tag in ('normal','irony','harassment','hate','threat','ambiguous','quotation')),
 tags text[] not null default '{}' check(cardinality(tags)<=7 and tags <@ array['normal','irony','harassment','hate','threat','ambiguous','quotation']::text[]),
 final_tag text check(final_tag in ('normal','irony','harassment','hate','threat','ambiguous','quotation')),
 status text not null default 'pending' check(status in ('pending','approved','hidden')),
 seed_code text unique, seed_note text,
 created_at timestamptz not null default now(), approved_at timestamptz,
 check((status='approved' and final_tag is not null) or status<>'approved')
);
create index kl_samples_author on public.kl_samples(author_id);
create index kl_samples_status_date on public.kl_samples(status,created_at desc);
create table public.kl_votes (
 sample_id uuid not null references public.kl_samples(id) on delete cascade,
 user_id uuid not null references public.kl_profiles(id) on delete cascade,
 tag text check(tag in ('normal','irony','harassment','hate','threat','ambiguous','quotation')),
 rationale text not null check(char_length(rationale) between 5 and 1000),
 created_at timestamptz not null default now(), primary key(sample_id,user_id)
);
create index kl_votes_user on public.kl_votes(user_id);
create table public.kl_comments (
 id uuid primary key default gen_random_uuid(), sample_id uuid not null references public.kl_samples(id) on delete cascade,
 user_id uuid not null references public.kl_profiles(id) on delete cascade,
 body text not null check(char_length(body) between 2 and 1200), created_at timestamptz not null default now(), hidden boolean not null default false
);
create index kl_comments_sample on public.kl_comments(sample_id,created_at);
create index kl_comments_user on public.kl_comments(user_id);
create table public.kl_likes (
 sample_id uuid not null references public.kl_samples(id) on delete cascade,
 user_id uuid not null references public.kl_profiles(id) on delete cascade, created_at timestamptz not null default now(),primary key(sample_id,user_id)
);
create index kl_likes_user on public.kl_likes(user_id);
create table public.kl_reports (
 id uuid primary key default gen_random_uuid(), sample_id uuid not null references public.kl_samples(id) on delete cascade,
 user_id uuid not null references public.kl_profiles(id) on delete cascade, reason text not null check(char_length(reason) between 5 and 1000),
 created_at timestamptz not null default now(), unique(sample_id,user_id)
);
create index kl_reports_user on public.kl_reports(user_id);
create table kl_private.admins(user_id uuid primary key references auth.users(id));
alter table kl_private.admins enable row level security;
create table kl_private.moderation_log(id bigint generated always as identity primary key,actor uuid, sample_id uuid,action text,created_at timestamptz default now());
alter table kl_private.moderation_log enable row level security;
alter table public.kl_profiles enable row level security;
alter table public.kl_samples enable row level security;
alter table public.kl_votes enable row level security;
alter table public.kl_comments enable row level security;
alter table public.kl_likes enable row level security;
alter table public.kl_reports enable row level security;
create policy profile_read on public.kl_profiles for select to anon,authenticated using(true);
create policy profile_update on public.kl_profiles for update to authenticated using((select auth.uid())=id) with check((select auth.uid())=id);
create policy sample_read on public.kl_samples for select to anon,authenticated using(status in ('pending','approved'));
create policy vote_read on public.kl_votes for select to authenticated using(user_id=(select auth.uid()));
create policy comment_read on public.kl_comments for select to anon,authenticated using(not hidden and exists(select 1 from public.kl_samples s where s.id=sample_id and s.status='approved'));
create policy like_read on public.kl_likes for select to authenticated using(user_id=(select auth.uid()));
create policy report_read on public.kl_reports for select to authenticated using(user_id=(select auth.uid()));
revoke all on public.kl_profiles,public.kl_samples,public.kl_votes,public.kl_comments,public.kl_likes,public.kl_reports from public,anon,authenticated;
grant select on public.kl_profiles,public.kl_samples,public.kl_comments to anon,authenticated;
grant select on public.kl_votes,public.kl_likes,public.kl_reports to authenticated;
grant update(display_name,bio) on public.kl_profiles to authenticated;
-- No direct write grants for corpus, votes, likes, comments or moderation state.
create function kl_private.new_profile() returns trigger language plpgsql security definer set search_path='' as $$
begin insert into public.kl_profiles(id,display_name) values(new.id,'Researcher-'||left(new.id::text,6));return new;end;$$;
revoke all on function kl_private.new_profile() from public,anon,authenticated;
create trigger kl_on_signup after insert on auth.users for each row execute function kl_private.new_profile();
insert into public.kl_profiles(id) select id from auth.users on conflict do nothing;
create function kl_private.require_user() returns uuid language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid();begin
 if uid is null or not exists(select 1 from auth.users where id=uid and is_anonymous is not true and (banned_until is null or banned_until<now())) then raise exception 'login_required';end if;return uid;end;$$;
create function kl_private.submit_sample(p_text text,p_translation text,p_context text,p_language text,p_tag text,p_tags text[]) returns uuid language plpgsql security definer set search_path='' as $$
declare uid uuid:=kl_private.require_user();sid uuid;begin
 perform pg_advisory_xact_lock(hashtextextended(uid::text,7));
 if (select count(*) from public.kl_samples where author_id=uid and created_at>now()-interval '1 day')>=10 then raise exception 'submission_daily_limit';end if;
 if exists(select 1 from public.kl_samples where lower(btrim(text))=lower(btrim(p_text)) and status<>'hidden') then raise exception 'duplicate_sample';end if;
 insert into public.kl_samples(author_id,text,translation,context,language,proposed_tag,tags) values(uid,btrim(p_text),btrim(p_translation),btrim(p_context),p_language,p_tag,p_tags) returning id into sid;return sid;end;$$;
create function kl_private.cast_vote(p_sample uuid,p_tag text,p_reason text) returns void language plpgsql security definer set search_path='' as $$
declare uid uuid:=kl_private.require_user();s public.kl_samples;total_n bigint;top_n bigint;winner text;begin
 select * into s from public.kl_samples where id=p_sample for update;
 if not found or s.status<>'pending' then raise exception 'review_closed';end if;
 if s.author_id=uid then raise exception 'self_review_forbidden';end if;
 if exists(select 1 from public.kl_votes where sample_id=p_sample and user_id=uid) then raise exception 'already_reviewed';end if;
 if (select count(*) from public.kl_votes where user_id=uid and created_at>now()-interval '1 day')>=100 then raise exception 'review_daily_limit';end if;
 insert into public.kl_votes(sample_id,user_id,tag,rationale) values(p_sample,uid,p_tag,btrim(p_reason));
 select count(*) into total_n from public.kl_votes where sample_id=p_sample;
 select tag,count(*) into winner,top_n from public.kl_votes where sample_id=p_sample and tag is not null group by tag order by count(*) desc,tag limit 1;
 if total_n>=5 and top_n*5>=total_n*3 then
 update public.kl_samples set status='approved',final_tag=winner,approved_at=now() where id=p_sample;
 insert into kl_private.moderation_log(actor,sample_id,action) values(uid,p_sample,'community_approved:'||winner);end if;end;$$;
create function kl_private.add_comment(p_sample uuid,p_body text) returns uuid language plpgsql security definer set search_path='' as $$
declare uid uuid:=kl_private.require_user();cid uuid;begin
 perform pg_advisory_xact_lock(hashtextextended(uid::text,8));
 if not exists(select 1 from public.kl_samples where id=p_sample and status='approved') then raise exception 'approved_only';end if;
 if (select count(*) from public.kl_comments where user_id=uid and created_at>now()-interval '1 hour')>=20 then raise exception 'comment_hourly_limit';end if;
 insert into public.kl_comments(sample_id,user_id,body) values(p_sample,uid,btrim(p_body)) returning id into cid;return cid;end;$$;
create function kl_private.toggle_like(p_sample uuid) returns boolean language plpgsql security definer set search_path='' as $$
declare uid uuid:=kl_private.require_user();begin
 perform pg_advisory_xact_lock(hashtextextended(uid::text,9));
 if not exists(select 1 from public.kl_samples where id=p_sample and status='approved') then raise exception 'approved_only';end if;
 if exists(select 1 from public.kl_likes where sample_id=p_sample and user_id=uid) then delete from public.kl_likes where sample_id=p_sample and user_id=uid;return false;end if;
 insert into public.kl_likes(sample_id,user_id) values(p_sample,uid);return true;end;$$;
create function kl_private.report_sample(p_sample uuid,p_reason text) returns void language plpgsql security definer set search_path='' as $$
declare uid uuid:=kl_private.require_user();begin
 if not exists(select 1 from public.kl_samples where id=p_sample and status in ('pending','approved')) then raise exception 'not_found';end if;
 insert into public.kl_reports(sample_id,user_id,reason) values(p_sample,uid,btrim(p_reason));end;$$;
create function kl_private.delete_comment(p_comment uuid) returns void language plpgsql security definer set search_path='' as $$
declare uid uuid:=kl_private.require_user();begin delete from public.kl_comments where id=p_comment and user_id=uid;end;$$;
-- Public aggregates reveal counts, not reviewer identities or private email addresses.
create function public.kl_stats() returns jsonb language sql stable security definer set search_path='' as $$
select jsonb_build_object('samples',coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'votes',(select count(*) from public.kl_votes v where v.sample_id=s.id),'ballots',(select coalesce(jsonb_object_agg(tag,n),'{}') from (select coalesce(tag,'reject') tag,count(*) n from public.kl_votes where sample_id=s.id group by tag) x),'likes',(select count(*) from public.kl_likes l where l.sample_id=s.id),'comments',(select count(*) from public.kl_comments c where c.sample_id=s.id and not hidden))) from public.kl_samples s where s.status in ('pending','approved')),'[]'),'contributors',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'submitted',(select count(*) from public.kl_samples s where s.author_id=p.id and s.status<>'hidden'),'accepted',(select count(*) from public.kl_samples s where s.author_id=p.id and s.status='approved'),'reviews',(select count(*) from public.kl_votes v where v.user_id=p.id))) from public.kl_profiles p),'[]'));
$$;
-- These wrappers run as INVOKER; only authenticated users can reach privileged helpers.
create function public.kl_submit(p_text text,p_translation text,p_context text,p_language text,p_tag text,p_tags text[]) returns uuid language sql security invoker set search_path='' as $$select kl_private.submit_sample(p_text,p_translation,p_context,p_language,p_tag,p_tags);$$;
create function public.kl_vote(p_sample uuid,p_tag text,p_reason text) returns void language sql security invoker set search_path='' as $$select kl_private.cast_vote(p_sample,p_tag,p_reason);$$;
create function public.kl_comment(p_sample uuid,p_body text) returns uuid language sql security invoker set search_path='' as $$select kl_private.add_comment(p_sample,p_body);$$;
create function public.kl_like(p_sample uuid) returns boolean language sql security invoker set search_path='' as $$select kl_private.toggle_like(p_sample);$$;
create function public.kl_report(p_sample uuid,p_reason text) returns void language sql security invoker set search_path='' as $$select kl_private.report_sample(p_sample,p_reason);$$;
create function public.kl_delete_comment(p_comment uuid) returns void language sql security invoker set search_path='' as $$select kl_private.delete_comment(p_comment);$$;
create function kl_private.admin_action(p_sample uuid,p_action text) returns void language plpgsql security definer set search_path='' as $$
declare uid uuid:=kl_private.require_user();begin
 if not exists(select 1 from kl_private.admins where user_id=uid) then raise exception 'admin_only';end if;
 if p_action not in ('hide','reopen') then raise exception 'invalid_action';end if;
 perform 1 from public.kl_samples where id=p_sample for update;
 update public.kl_samples set status=case when p_action='hide' then 'hidden' else 'pending' end,final_tag=null,approved_at=null where id=p_sample;
 if p_action='reopen' then delete from public.kl_votes where sample_id=p_sample;end if;
 insert into kl_private.moderation_log(actor,sample_id,action) values(uid,p_sample,p_action);end;$$;
create function public.kl_admin_action(p_sample uuid,p_action text) returns void language sql security invoker set search_path='' as $$select kl_private.admin_action(p_sample,p_action);$$;
create function kl_private.admin_reports() returns jsonb language plpgsql stable security definer set search_path='' as $$
declare uid uuid:=kl_private.require_user();begin
 if not exists(select 1 from kl_private.admins where user_id=uid) then raise exception 'admin_only';end if;
 return coalesce((select jsonb_agg(jsonb_build_object('id',r.id,'sample_id',r.sample_id,'reason',r.reason,'created_at',r.created_at,'text',s.text,'status',s.status)) from public.kl_reports r join public.kl_samples s on s.id=r.sample_id),'[]');end;$$;
create function public.kl_admin_reports() returns jsonb language sql stable security invoker set search_path='' as $$select kl_private.admin_reports();$$;
revoke all on all functions in schema kl_private from public,anon,authenticated;
grant execute on function kl_private.require_user(),kl_private.submit_sample(text,text,text,text,text,text[]),kl_private.cast_vote(uuid,text,text),kl_private.add_comment(uuid,text),kl_private.toggle_like(uuid),kl_private.report_sample(uuid,text),kl_private.delete_comment(uuid),kl_private.admin_action(uuid,text),kl_private.admin_reports() to authenticated;
revoke all on function public.kl_stats() from public;
grant execute on function public.kl_stats() to anon,authenticated;
revoke all on function public.kl_submit(text,text,text,text,text,text[]),public.kl_vote(uuid,text,text),public.kl_comment(uuid,text),public.kl_like(uuid),public.kl_report(uuid,text),public.kl_delete_comment(uuid),public.kl_admin_action(uuid,text),public.kl_admin_reports() from public,anon;
grant execute on function public.kl_submit(text,text,text,text,text,text[]),public.kl_vote(uuid,text,text),public.kl_comment(uuid,text),public.kl_like(uuid),public.kl_report(uuid,text),public.kl_delete_comment(uuid),public.kl_admin_action(uuid,text),public.kl_admin_reports() to authenticated;

-- Read-only aggregate helper is private; only its invoker wrapper is exposed.
alter function public.kl_stats() set schema kl_private;
revoke all on function kl_private.kl_stats() from public;
grant usage on schema kl_private to anon;
grant execute on function kl_private.kl_stats() to anon,authenticated;
create function public.kl_stats() returns jsonb language sql stable security invoker set search_path='' as $$select kl_private.kl_stats();$$;
revoke all on function public.kl_stats() from public;
grant execute on function public.kl_stats() to anon,authenticated;
