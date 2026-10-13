-- Once both members have joined, either member can start the shared game.
create or replace function public.onlyus_set_ready(p_code text,p_ready boolean)
returns jsonb language plpgsql security definer set search_path=public,auth as $$
declare r public.onlyus_rooms%rowtype; n integer;
begin
 if not public.onlyus_is_member(p_code) then raise exception 'Unauthorized room membership'; end if;
 select * into r from public.onlyus_rooms where code=p_code for update;
 if not found or r.expires_at<now() then raise exception 'Room expired'; end if;
 if r.status<>'lobby' then return public.onlyus_get_state(p_code); end if;
 select count(*) into n from public.onlyus_players where room_code=p_code;
 if n<>2 then raise exception 'Both players need to join before starting'; end if;
 update public.onlyus_players set ready=p_ready where room_code=p_code and user_id=auth.uid();
 if p_ready then
   update public.onlyus_rooms set status='playing' where code=p_code and status='lobby';
 end if;
 return public.onlyus_get_state(p_code);
end $$;

revoke all on function public.onlyus_set_ready(text,boolean) from public,anon;
grant execute on function public.onlyus_set_ready(text,boolean) to authenticated;
