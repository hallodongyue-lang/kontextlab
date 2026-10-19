alter table public.kl_profiles add column onboarding_step smallint not null default 0 check(onboarding_step between 0 and 5), add column onboarding_completed_at timestamptz;
grant update(onboarding_step,onboarding_completed_at) on public.kl_profiles to authenticated;
