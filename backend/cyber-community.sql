alter table public.kl_samples add column hashtags text[] not null default '{}', add column withdrawn_at timestamptz, add column withdrawal_reason text, add column withdrawal_snapshot jsonb;
alter table public.kl_samples drop constraint kl_samples_status_check;
alter table public.kl_samples add constraint kl_samples_status_check check(status in ('pending','approved','withdrawn','hidden'));
alter table public.kl_samples add constraint kl_hashtags_limit check(cardinality(hashtags)<=8);
alter table public.kl_likes add column value smallint not null default 1 check(value in (-1,1)), add column reason text check(reason in ('context_incomplete','label_disputed','low_quality','other'));
create index kl_votes_recent on public.kl_votes(created_at desc,sample_id);
-- Existing editorial examples gain their proposed label as a hashtag, with no fabricated votes.
update public.kl_samples set hashtags=array[proposed_tag] where cardinality(hashtags)=0;
drop policy sample_read on public.kl_samples;
create policy sample_read on public.kl_samples for select to anon,authenticated using(status in ('pending','approved','withdrawn'));
drop policy comment_read on public.kl_comments;
create policy comment_read on public.kl_comments for select to anon,authenticated using(not hidden and exists(select 1 from public.kl_samples s where s.id=sample_id and s.status in ('approved','withdrawn')));
create function kl_private.normalize_hashtags() returns trigger language plpgsql security invoker set search_path='' as $$
declare raw text[];begin
 raw:=new.hashtags||array[new.proposed_tag]||coalesce((select array_agg(m[1]) from regexp_matches(new.text,'#([[:alnum:]_]{1,32})','g') m),'{}');
 if exists(select 1 from unnest(raw) h where char_length(ltrim(btrim(h),'#'))>32 or ltrim(btrim(h),'#') !~ '^[[:alnum:]_]+$') then raise exception 'invalid_hashtag';end if;
 select coalesce(array_agg(h order by h),'{}') into new.hashtags from (select distinct lower(ltrim(btrim(x),'#')) h from unnest(raw) x where btrim(x)<>'') q;
 if cardinality(new.hashtags)>8 then raise exception 'too_many_hashtags';end if;return new;end;$$;
revoke all on function kl_private.normalize_hashtags() from public,anon,authenticated;
create trigger kl_hashtags before insert or update of hashtags,text,proposed_tag on public.kl_samples for each row execute function kl_private.normalize_hashtags();
create function kl_private.submit_tagged(p_text text,p_translation text,p_context text,p_language text,p_tag text,p_tags text[],p_hashtags text[]) returns uuid language plpgsql security definer set search_path='' as $$
declare sid uuid;begin
 sid:=kl_private.submit_sample(p_text,p_translation,p_context,p_language,p_tag,p_tags);
 update public.kl_samples set hashtags=p_hashtags where id=sid;return sid;end;$$;
create function public.kl_submit_tagged(p_text text,p_translation text,p_context text,p_language text,p_tag text,p_tags text[],p_hashtags text[]) returns uuid language sql security invoker set search_path='' as $$select kl_private.submit_tagged(p_text,p_translation,p_context,p_language,p_tag,p_tags,p_hashtags);$$;
revoke all on function kl_private.submit_tagged(text,text,text,text,text,text[],text[]),public.kl_submit_tagged(text,text,text,text,text,text[],text[]) from public,anon;
grant execute on function kl_private.submit_tagged(text,text,text,text,text,text[],text[]),public.kl_submit_tagged(text,text,text,text,text,text[],text[]) to authenticated;
create function kl_private.react(p_sample uuid,p_value int,p_reason text) returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid:=kl_private.require_user();s public.kl_samples;old_value int;positive bigint;negative bigint;total_n bigint;reasons jsonb;begin
 if p_value not in (-1,1) or p_value is null then raise exception 'invalid_reaction';end if;
 if p_value=-1 and (p_reason is null or p_reason not in ('context_incomplete','label_disputed','low_quality','other')) then raise exception 'dislike_reason_required';end if;
 select * into s from public.kl_samples where id=p_sample for update;
 if not found or s.status<>'approved' then raise exception 'reactions_closed';end if;
 select value into old_value from public.kl_likes where sample_id=p_sample and user_id=uid;
 if old_value=p_value then delete from public.kl_likes where sample_id=p_sample and user_id=uid;
 else insert into public.kl_likes(sample_id,user_id,value,reason) values(p_sample,uid,p_value,case when p_value=-1 then p_reason else null end)
 on conflict(sample_id,user_id) do update set value=excluded.value,reason=excluded.reason,created_at=now();end if;
 select count(*) filter(where value=1),count(*) filter(where value=-1),count(*) into positive,negative,total_n from public.kl_likes where sample_id=p_sample;
 if total_n>=5 and negative*5>total_n*3 then
 select coalesce(jsonb_object_agg(reason,n),'{}') into reasons from (select coalesce(reason,'other') reason,count(*) n from public.kl_likes where sample_id=p_sample and value=-1 group by reason) r;
 update public.kl_samples set status='withdrawn',withdrawn_at=now(),withdrawal_reason='community_disapproval',withdrawal_snapshot=jsonb_build_object('positive',positive,'negative',negative,'total',total_n,'ratio',negative::numeric/total_n,'reasons',reasons) where id=p_sample;
 insert into kl_private.moderation_log(actor,sample_id,action) values(uid,p_sample,'community_withdrawn:'||negative||'/'||total_n);
 end if;
 return jsonb_build_object('positive',positive,'negative',negative,'total',total_n,'withdrawn',total_n>=5 and negative*5>total_n*3);end;$$;
create function public.kl_react(p_sample uuid,p_value int,p_reason text default null) returns jsonb language sql security invoker set search_path='' as $$select kl_private.react(p_sample,p_value,p_reason);$$;
revoke all on function kl_private.react(uuid,int,text),public.kl_react(uuid,int,text) from public,anon;
grant execute on function kl_private.react(uuid,int,text),public.kl_react(uuid,int,text) to authenticated;
-- Preserve old clients' like/unlike API while keeping a single reaction per account.
create or replace function kl_private.toggle_like(p_sample uuid) returns boolean language plpgsql security definer set search_path='' as $$
declare uid uuid:=kl_private.require_user();result jsonb;begin
 result:=kl_private.react(p_sample,1,null);return exists(select 1 from public.kl_likes where sample_id=p_sample and user_id=uid and value=1);end;$$;
create or replace function kl_private.add_comment(p_sample uuid,p_body text) returns uuid language plpgsql security definer set search_path='' as $$
declare uid uuid:=kl_private.require_user();cid uuid;begin
 perform pg_advisory_xact_lock(hashtextextended(uid::text,8));
 if not exists(select 1 from public.kl_samples where id=p_sample and status in ('approved','withdrawn')) then raise exception 'approved_only';end if;
 if (select count(*) from public.kl_comments where user_id=uid and created_at>now()-interval '1 hour')>=20 then raise exception 'comment_hourly_limit';end if;
 insert into public.kl_comments(sample_id,user_id,body) values(p_sample,uid,btrim(p_body)) returning id into cid;return cid;end;$$;
create or replace function kl_private.report_sample(p_sample uuid,p_reason text) returns void language plpgsql security definer set search_path='' as $$
declare uid uuid:=kl_private.require_user();begin
 if not exists(select 1 from public.kl_samples where id=p_sample and status in ('pending','approved','withdrawn')) then raise exception 'not_found';end if;
 insert into public.kl_reports(sample_id,user_id,reason) values(p_sample,uid,btrim(p_reason));end;$$;
create or replace function kl_private.admin_action(p_sample uuid,p_action text) returns void language plpgsql security definer set search_path='' as $$
declare uid uuid:=kl_private.require_user();begin
 if not exists(select 1 from kl_private.admins where user_id=uid) then raise exception 'admin_only';end if;
 if p_action not in ('hide','reopen') then raise exception 'invalid_action';end if;
 perform 1 from public.kl_samples where id=p_sample for update;
 update public.kl_samples set status=case when p_action='hide' then 'hidden' else 'pending' end,final_tag=null,approved_at=null,withdrawn_at=null,withdrawal_reason=null,withdrawal_snapshot=null where id=p_sample;
 if p_action='reopen' then delete from public.kl_votes where sample_id=p_sample;delete from public.kl_likes where sample_id=p_sample;end if;
 insert into kl_private.moderation_log(actor,sample_id,action) values(uid,p_sample,p_action);end;$$;
create or replace function kl_private.kl_stats() returns jsonb language sql stable security definer set search_path='' as $$
select jsonb_build_object('samples',coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'votes',(select count(*) from public.kl_votes v where v.sample_id=s.id),'ballots',(select coalesce(jsonb_object_agg(tag,n),'{}') from (select coalesce(tag,'reject') tag,count(*) n from public.kl_votes where sample_id=s.id group by tag) x),'likes',(select count(*) from public.kl_likes l where l.sample_id=s.id and value=1),'dislikes',(select count(*) from public.kl_likes l where l.sample_id=s.id and value=-1),'comments',(select count(*) from public.kl_comments c where c.sample_id=s.id and not hidden))) from public.kl_samples s where s.status in ('pending','approved','withdrawn')),'[]'),'contributors',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'submitted',(select count(*) from public.kl_samples s where s.author_id=p.id and s.status<>'hidden'),'accepted',(select count(*) from public.kl_samples s where s.author_id=p.id and s.status='approved'),'reviews',(select count(*) from public.kl_votes v where v.user_id=p.id))) from public.kl_profiles p),'[]'),'trending',coalesce((select jsonb_agg(to_jsonb(r)) from (select h as hashtag,count(*) as annotations,count(distinct s.id) as samples,max(v.created_at) as last_annotated from public.kl_votes v join public.kl_samples s on s.id=v.sample_id cross join lateral unnest(s.hashtags) h where v.created_at>=now()-interval '7 days' and s.status in ('approved','pending') group by h order by count(*) desc,max(v.created_at) desc,h limit 10) r),'[]'));
$$;
