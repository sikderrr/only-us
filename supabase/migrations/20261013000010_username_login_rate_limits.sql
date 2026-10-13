-- Short-lived, hashed fingerprints prevent username login brute-force attempts.
-- Fingerprints are purged after 24 hours and never contain raw IPs or usernames.
create table if not exists public.onlyus_username_login_limits (
  fingerprint text primary key check (fingerprint ~ '^[a-f0-9]{64}$'),
  window_started_at timestamptz not null default now(),
  failed_attempts integer not null default 0 check (failed_attempts between 0 and 5),
  updated_at timestamptz not null default now()
);
alter table public.onlyus_username_login_limits enable row level security;
revoke all on public.onlyus_username_login_limits from public,anon,authenticated;

create or replace function public.onlyus_username_login_limit(p_fingerprint text,p_action text)
returns boolean
language plpgsql
security definer
set search_path=public
as $$
declare existing public.onlyus_username_login_limits%rowtype;
begin
  if p_fingerprint !~ '^[a-f0-9]{64}$' or p_action not in ('check','failure','success') then
    raise exception 'Invalid login throttle request';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_fingerprint,41027));
  delete from public.onlyus_username_login_limits where updated_at < now() - interval '24 hours';

  if p_action='success' then
    delete from public.onlyus_username_login_limits where fingerprint=p_fingerprint;
    return true;
  end if;

  select * into existing from public.onlyus_username_login_limits where fingerprint=p_fingerprint for update;
  if p_action='check' then
    return not found or existing.window_started_at < now() - interval '15 minutes' or existing.failed_attempts < 5;
  end if;

  if not found or existing.window_started_at < now() - interval '15 minutes' then
    insert into public.onlyus_username_login_limits(fingerprint,window_started_at,failed_attempts,updated_at)
      values(p_fingerprint,now(),1,now())
      on conflict(fingerprint) do update set window_started_at=excluded.window_started_at,failed_attempts=1,updated_at=now();
    return true;
  end if;

  update public.onlyus_username_login_limits
    set failed_attempts=least(failed_attempts+1,5),updated_at=now()
    where fingerprint=p_fingerprint;
  return existing.failed_attempts + 1 < 5;
end;
$$;
revoke all on function public.onlyus_username_login_limit(text,text) from public,anon,authenticated;
grant execute on function public.onlyus_username_login_limit(text,text) to service_role;
