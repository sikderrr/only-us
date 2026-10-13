-- Private, short-lived room messages and durable last-seen timestamps.
alter table public.onlyus_players
  add column if not exists last_seen_at timestamptz not null default now();

create table if not exists public.onlyus_messages (
  id bigint generated always as identity primary key,
  room_code text not null references public.onlyus_rooms(code) on delete cascade,
  player_id uuid not null references auth.users(id) on delete cascade,
  body text not null check (char_length(body) between 1 and 1000),
  created_at timestamptz not null default now()
);
create index if not exists onlyus_messages_room_id_idx on public.onlyus_messages(room_code,id desc);
alter table public.onlyus_messages enable row level security;
revoke all on public.onlyus_messages from anon,authenticated;

create or replace function public.onlyus_get_state(p_code text)
returns jsonb language plpgsql security definer set search_path=public,auth as $$
declare r public.onlyus_rooms%rowtype;
begin
 if not public.onlyus_is_member(p_code) then raise exception 'Unauthorized room membership'; end if;
 select * into r from public.onlyus_rooms where code=p_code;
 if not found or r.expires_at<now() then raise exception 'Room expired'; end if;
 return jsonb_build_object(
   'room_code',r.code,'status',r.status,
   'players',(select coalesce(jsonb_agg(jsonb_build_object(
     'id',p.user_id,'name',p.name,'avatar',p.avatar,'ready',p.ready,
     'connected',true,'last_seen_at',p.last_seen_at) order by p.seat),'[]'::jsonb)
     from public.onlyus_players p where p.room_code=p_code),
   'turn_index',r.turn_index,'round',r.round,'scores',r.scores,'category',r.category,
   'prompt_kind',r.prompt_kind,'prompt_id',r.prompt_id,'prompt_text',r.prompt_text,
   'prompt_category',r.prompt_category,'prompt_player',r.prompt_player,
   'prompt_response',r.prompt_response,'prompt_done',r.prompt_done,'recent_ids',r.recent_ids
 );
end $$;

create or replace function public.onlyus_touch_presence(p_code text)
returns timestamptz language plpgsql security definer set search_path=public,auth as $$
declare touched timestamptz;
begin
 update public.onlyus_players set last_seen_at=now()
 where room_code=p_code and user_id=auth.uid() and public.onlyus_is_member(p_code)
 returning last_seen_at into touched;
 if not found then raise exception 'Unauthorized room membership'; end if;
 return touched;
end $$;

create or replace function public.onlyus_list_messages(p_code text)
returns jsonb language plpgsql security definer set search_path=public,auth as $$
declare room_status text; room_expires timestamptz;
begin
 if not public.onlyus_is_member(p_code) then raise exception 'Unauthorized room membership'; end if;
 select status,expires_at into room_status,room_expires from public.onlyus_rooms where code=p_code;
 if room_status is null or room_expires<now() then raise exception 'Room expired'; end if;
 if room_status='finished' then return '[]'::jsonb; end if;
 return (select coalesce(jsonb_agg(to_jsonb(m) order by m.id),'[]'::jsonb)
   from (select id,player_id,body,created_at from public.onlyus_messages
     where room_code=p_code order by id desc limit 100) m);
end $$;

create or replace function public.onlyus_send_message(p_code text,p_body text)
returns jsonb language plpgsql security definer set search_path=public,auth as $$
declare r public.onlyus_rooms%rowtype; body_text text; sent public.onlyus_messages%rowtype;
begin
 if not public.onlyus_is_member(p_code) then raise exception 'Unauthorized room membership'; end if;
 body_text=trim(coalesce(p_body,''));
 if char_length(body_text)<1 or char_length(body_text)>1000 then
   raise exception 'Messages must be between 1 and 1000 characters';
 end if;
 select * into r from public.onlyus_rooms where code=p_code for update;
 if not found or r.expires_at<now() or r.status='finished' then raise exception 'Room is not active'; end if;
 insert into public.onlyus_messages(room_code,player_id,body)
   values(p_code,auth.uid(),body_text) returning * into sent;
 return to_jsonb(sent);
end $$;

revoke all on function public.onlyus_get_state(text),
  public.onlyus_touch_presence(text),public.onlyus_list_messages(text),
  public.onlyus_send_message(text,text) from public,anon;
grant execute on function public.onlyus_get_state(text),
  public.onlyus_touch_presence(text),public.onlyus_list_messages(text),
  public.onlyus_send_message(text,text) to authenticated;
