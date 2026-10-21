-- Research protocol 1.0. Existing text is never exported as a review rationale without opt-in.
alter table public.kl_samples add column if not exists research_meta jsonb not null default '{}';
alter table public.kl_votes add column if not exists research_consent boolean not null default false;
create table if not exists public.kl_experiments (
 id uuid primary key default gen_random_uuid(), user_id uuid not null references public.kl_profiles(id) on delete cascade,
 protocol text not null check(protocol='context-1.0'), item text not null check(item in ('toll','genie','klar')),
 relation text not null check(relation in ('friends','hierarchy','strangers')),
 initial text not null check(initial in ('praise','irony','uncertain')), final text not null check(final in ('praise','irony','uncertain')),
 reason text not null check(char_length(reason) between 5 and 1000), consent boolean not null default false,
 created_at timestamptz not null default now(), withdrawn_at timestamptz,
 unique(user_id,protocol,item,relation)
);
alter table public.kl_experiments enable row level security;
revoke all on public.kl_experiments from public,anon,authenticated;
grant select,insert on public.kl_experiments to authenticated;
grant update(consent,withdrawn_at) on public.kl_experiments to authenticated;
create policy experiment_read on public.kl_experiments for select to authenticated using(user_id=(select auth.uid()));
create policy experiment_insert on public.kl_experiments for insert to authenticated with check(user_id=(select auth.uid()) and withdrawn_at is null);
create policy experiment_update on public.kl_experiments for update to authenticated using(user_id=(select auth.uid())) with check(user_id=(select auth.uid()));
create index if not exists kl_experiments_user on public.kl_experiments(user_id);
grant update(research_consent) on public.kl_votes to authenticated;
create policy vote_consent_update on public.kl_votes for update to authenticated using(user_id=(select auth.uid())) with check(user_id=(select auth.uid()));
-- Only an author may describe their submission. Classification is still governed by existing consensus functions.
grant update(research_meta) on public.kl_samples to authenticated;
create policy sample_metadata_update on public.kl_samples for update to authenticated using(author_id=(select auth.uid())) with check(author_id=(select auth.uid()));
alter table public.kl_samples add constraint research_meta_shape check(jsonb_typeof(research_meta)='object' and octet_length(research_meta::text)<=2000);
create or replace function kl_private.research_data() returns jsonb language sql stable security definer set search_path='' as $$
select jsonb_build_object(
'reasons',coalesce((select jsonb_agg(jsonb_build_object('sample_id',v.sample_id,'tag',coalesce(v.tag,'reject'),'reason',v.rationale)) from public.kl_votes v join public.kl_samples s on s.id=v.sample_id where v.research_consent and s.status in ('approved','withdrawn')),'[]'::jsonb),
'experiments',coalesce((select jsonb_agg(to_jsonb(x)) from (select item,relation,initial,final,count(*) as n from public.kl_experiments where consent and withdrawn_at is null group by item,relation,initial,final) x),'[]'::jsonb));
$$;
revoke all on function kl_private.research_data() from public;
grant usage on schema kl_private to anon;
grant execute on function kl_private.research_data() to anon,authenticated;
create or replace function public.kl_research_data() returns jsonb language sql stable security invoker set search_path='' as $$select kl_private.research_data();$$;
revoke all on function public.kl_research_data() from public;
grant execute on function public.kl_research_data() to anon,authenticated;
-- Owner-initiated deletion, separate from reversible withdrawal.
grant delete on public.kl_experiments to authenticated;
create policy experiment_delete on public.kl_experiments for delete to authenticated using(user_id=(select auth.uid()));
