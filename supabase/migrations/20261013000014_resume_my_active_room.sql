-- Let a signed-in player recover a room after clearing site data or refreshing
-- on a device that joined before active-room recovery was added.
create index if not exists onlyus_players_user_room_idx
  on public.onlyus_players(user_id,room_code);

create or replace function public.onlyus_find_my_active_room()
returns text
language sql
stable
security definer
set search_path=public,auth
as $$
  select r.code
  from public.onlyus_rooms r
  join public.onlyus_players p on p.room_code=r.code
  where p.user_id=auth.uid()
    and r.status in ('lobby','playing')
    and r.expires_at>now()
  order by r.created_at desc
  limit 1;
$$;

revoke all on function public.onlyus_find_my_active_room() from public,anon;
grant execute on function public.onlyus_find_my_active_room() to authenticated;
