-- Only Us Phase 1. Run in Supabase SQL editor or via `supabase db push`.
create extension if not exists pgcrypto with schema extensions;
create table if not exists public.onlyus_rooms (
  code text primary key check (code ~ '^[A-HJ-NP-Z2-9]{6}$'),
  status text not null default 'lobby' check (status in ('lobby','playing','finished')),
  created_at timestamptz not null default now(), expires_at timestamptz not null default now()+interval '24 hours',
  turn_index integer not null default 0, round integer not null default 1,
  scores integer[] not null default array[0,0], category text not null default 'all',
  prompt_kind text, prompt_id text, prompt_text text, prompt_category text, prompt_player integer,
  prompt_done boolean not null default false, recent_ids text[] not null default '{}',
  resolved_by uuid, resolved_at timestamptz
);
create table if not exists public.onlyus_players (
  room_code text not null references public.onlyus_rooms(code) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade, seat integer not null check (seat in (0,1)),
  name text not null check (length(name) between 1 and 24), avatar text not null,
  ready boolean not null default false, joined_at timestamptz not null default now(),
  primary key(room_code,user_id), unique(room_code,seat)
);
create table if not exists public.onlyus_prompts (
  id text primary key, category text not null check (category in ('Cute','Romantic','Flirty','Funny','Deep')),
  kind text not null check (kind in ('truth','dare')), text text not null check (length(text) between 1 and 250)
);
alter table public.onlyus_rooms enable row level security;
alter table public.onlyus_players enable row level security;
alter table public.onlyus_prompts enable row level security;
revoke all on public.onlyus_rooms, public.onlyus_players, public.onlyus_prompts from anon, authenticated;

create or replace function public.onlyus_is_member(p_code text) returns boolean language sql stable security definer set search_path=public,auth as $$
 select exists(select 1 from public.onlyus_players where room_code=p_code and user_id=auth.uid()) $$;
revoke all on function public.onlyus_is_member(text) from public; grant execute on function public.onlyus_is_member(text) to authenticated;

create or replace function public.onlyus_create_room(p_code text,p_name text,p_avatar text) returns jsonb language plpgsql security definer set search_path=public,auth as $$
begin
 if auth.uid() is null then raise exception 'Sign in to create a room'; end if;
 if p_code !~ '^[A-HJ-NP-Z2-9]{6}$' then raise exception 'Invalid room code'; end if;
 insert into public.onlyus_rooms(code) values(p_code);
 insert into public.onlyus_players(room_code,user_id,seat,name,avatar) values(p_code,auth.uid(),0,left(trim(p_name),24),left(p_avatar,16));
 return public.onlyus_get_state(p_code);
end $$;
create or replace function public.onlyus_join_room(p_code text,p_name text,p_avatar text) returns jsonb language plpgsql security definer set search_path=public,auth as $$
declare r public.onlyus_rooms%rowtype; n integer;
begin
 if auth.uid() is null then raise exception 'Sign in to join a room'; end if;
 select * into r from public.onlyus_rooms where code=p_code for update;
 if not found then raise exception 'Invalid room code'; end if;
 if r.expires_at<now() then raise exception 'Room expired'; end if;
 if r.status<>'lobby' then raise exception 'Room already started'; end if;
 if exists(select 1 from public.onlyus_players where room_code=p_code and user_id=auth.uid()) then return public.onlyus_get_state(p_code); end if;
 select count(*) into n from public.onlyus_players where room_code=p_code;
 if n>=2 then raise exception 'Room full: two players only'; end if;
 insert into public.onlyus_players(room_code,user_id,seat,name,avatar) values(p_code,auth.uid(),n,left(trim(p_name),24),left(p_avatar,16));
 return public.onlyus_get_state(p_code);
end $$;
create or replace function public.onlyus_get_state(p_code text) returns jsonb language plpgsql security definer set search_path=public,auth as $$
declare r public.onlyus_rooms%rowtype;
begin
 if not public.onlyus_is_member(p_code) then raise exception 'Unauthorized room membership'; end if;
 select * into r from public.onlyus_rooms where code=p_code;
 if not found or r.expires_at<now() then raise exception 'Room expired'; end if;
 return jsonb_build_object('room_code',r.code,'status',r.status,'players',(select coalesce(jsonb_agg(jsonb_build_object('id',p.user_id,'name',p.name,'avatar',p.avatar,'ready',p.ready,'connected',true) order by p.seat),'[]'::jsonb) from public.onlyus_players p where p.room_code=p_code),'turn_index',r.turn_index,'round',r.round,'scores',r.scores,'category',r.category,'prompt_kind',r.prompt_kind,'prompt_id',r.prompt_id,'prompt_text',r.prompt_text,'prompt_category',r.prompt_category,'prompt_player',r.prompt_player,'prompt_done',r.prompt_done,'recent_ids',r.recent_ids);
end $$;
create or replace function public.onlyus_set_ready(p_code text,p_ready boolean) returns jsonb language plpgsql security definer set search_path=public,auth as $$
declare n integer; ready_n integer;
begin
 if not public.onlyus_is_member(p_code) then raise exception 'Unauthorized room membership'; end if;
 update public.onlyus_players set ready=p_ready where room_code=p_code and user_id=auth.uid();
 select count(*),count(*) filter(where ready) into n,ready_n from public.onlyus_players where room_code=p_code;
 if n=2 and ready_n=2 then update public.onlyus_rooms set status='playing' where code=p_code and status='lobby'; end if;
 return public.onlyus_get_state(p_code);
end $$;
create or replace function public.onlyus_take_turn(p_code text,p_kind text,p_category text) returns jsonb language plpgsql security definer set search_path=public,auth as $$
declare r public.onlyus_rooms%rowtype; my_index integer; picked public.onlyus_prompts%rowtype;
begin
 if p_kind not in ('truth','dare') or p_category not in ('all','Cute','Romantic','Flirty','Funny','Deep') then raise exception 'Invalid prompt selection'; end if;
 if not public.onlyus_is_member(p_code) then raise exception 'Unauthorized room membership'; end if;
 select * into r from public.onlyus_rooms where code=p_code for update;
 select seat into my_index from public.onlyus_players where room_code=p_code and user_id=auth.uid();
 if r.status<>'playing' or r.prompt_text is not null or r.turn_index<>my_index then raise exception 'Not your turn'; end if;
 select * into picked from public.onlyus_prompts where kind=p_kind and (p_category='all' or category=p_category) and not(id=any(r.recent_ids)) order by random() limit 1;
 if not found then select * into picked from public.onlyus_prompts where kind=p_kind and (p_category='all' or category=p_category) order by random() limit 1; end if;
 if not found then raise exception 'No prompts in this category'; end if;
 update public.onlyus_rooms set category=p_category,prompt_kind=p_kind,prompt_id=picked.id,prompt_text=picked.text,prompt_category=picked.category,prompt_player=my_index,prompt_done=false where code=p_code;
 return public.onlyus_get_state(p_code);
end $$;
create or replace function public.onlyus_resolve_prompt(p_code text,p_done boolean) returns jsonb language plpgsql security definer set search_path=public,auth as $$
declare r public.onlyus_rooms%rowtype; idx integer;
begin
 if not public.onlyus_is_member(p_code) then raise exception 'Unauthorized room membership'; end if;
 select * into r from public.onlyus_rooms where code=p_code for update;
 if r.status<>'playing' or r.prompt_text is null or r.prompt_done then raise exception 'Prompt already resolved'; end if;
 if p_done then
   update public.onlyus_rooms set scores=array[ scores[1]+case when prompt_player=0 then 1 else 0 end, scores[2]+case when prompt_player=1 then 1 else 0 end ],prompt_done=true,resolved_by=auth.uid(),resolved_at=now(),recent_ids=(array_append(recent_ids,prompt_id))[greatest(1,array_length(recent_ids,1)-19):array_length(recent_ids,1)+1] where code=p_code;
 else
   update public.onlyus_rooms set turn_index=1-turn_index,round=round+1,recent_ids=(array_append(recent_ids,prompt_id))[greatest(1,array_length(recent_ids,1)-19):array_length(recent_ids,1)+1],prompt_kind=null,prompt_id=null,prompt_text=null,prompt_category=null,prompt_player=null,prompt_done=false where code=p_code;
 end if;
 return public.onlyus_get_state(p_code);
end $$;
create or replace function public.onlyus_continue(p_code text) returns jsonb language plpgsql security definer set search_path=public,auth as $$
begin
 if not public.onlyus_is_member(p_code) then raise exception 'Unauthorized room membership'; end if;
 update public.onlyus_rooms set turn_index=1-turn_index,round=round+1,prompt_kind=null,prompt_id=null,prompt_text=null,prompt_category=null,prompt_player=null,prompt_done=false where code=p_code and status='playing' and prompt_done=true;
 if not found then raise exception 'Prompt is not complete'; end if;
 return public.onlyus_get_state(p_code);
end $$;
create or replace function public.onlyus_finish(p_code text) returns jsonb language plpgsql security definer set search_path=public,auth as $$
begin
 if not public.onlyus_is_member(p_code) then raise exception 'Unauthorized room membership'; end if;
 update public.onlyus_rooms set status='finished' where code=p_code and status='playing';
 return public.onlyus_get_state(p_code);
end $$;
create or replace function public.onlyus_rematch(p_code text) returns jsonb language plpgsql security definer set search_path=public,auth as $$
begin
 if not public.onlyus_is_member(p_code) then raise exception 'Unauthorized room membership'; end if;
 update public.onlyus_rooms set status='lobby',turn_index=0,round=1,scores=array[0,0],prompt_kind=null,prompt_id=null,prompt_text=null,prompt_category=null,prompt_player=null,prompt_done=false,recent_ids='{}',expires_at=now()+interval '24 hours' where code=p_code and status='finished';
 update public.onlyus_players set ready=false where room_code=p_code;
 return public.onlyus_get_state(p_code);
end $$;
revoke all on function public.onlyus_create_room(text,text,text),public.onlyus_join_room(text,text,text),public.onlyus_get_state(text),public.onlyus_set_ready(text,boolean),public.onlyus_take_turn(text,text,text),public.onlyus_resolve_prompt(text,boolean),public.onlyus_continue(text),public.onlyus_finish(text),public.onlyus_rematch(text) from public,anon;
grant execute on function public.onlyus_create_room(text,text,text),public.onlyus_join_room(text,text,text),public.onlyus_get_state(text),public.onlyus_set_ready(text,boolean),public.onlyus_take_turn(text,text,text),public.onlyus_resolve_prompt(text,boolean),public.onlyus_continue(text),public.onlyus_finish(text),public.onlyus_rematch(text) to authenticated;

-- Private Realtime channels use topic `room:CODE`; only members can subscribe or broadcast.
create policy "only room members read realtime messages" on realtime.messages for select to authenticated
using (split_part(realtime.topic(),':',1)='room' and public.onlyus_is_member(split_part(realtime.topic(),':',2)));
create policy "only room members send realtime messages" on realtime.messages for insert to authenticated
with check (split_part(realtime.topic(),':',1)='room' and public.onlyus_is_member(split_part(realtime.topic(),':',2)));
-- Schedule this function using Supabase Cron (daily). It removes expired rooms and child membership rows.
create or replace function public.onlyus_cleanup_expired() returns integer language plpgsql security definer set search_path=public as $$
declare n integer; begin delete from public.onlyus_rooms where expires_at<now(); get diagnostics n=row_count; return n; end $$;
revoke all on function public.onlyus_cleanup_expired() from public,anon,authenticated;
