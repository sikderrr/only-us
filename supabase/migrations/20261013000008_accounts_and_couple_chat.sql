-- Persistent accounts, couple membership, and a private conversation that survives game rooms.
create table if not exists public.onlyus_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null check (char_length(display_name) between 1 and 24),
  avatar text not null default '💗',
  last_seen_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.onlyus_profiles enable row level security;
revoke all on public.onlyus_profiles from anon, authenticated;

create table if not exists public.onlyus_couples (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now()
);
create table if not exists public.onlyus_couple_members (
  couple_id uuid not null references public.onlyus_couples(id) on delete cascade,
  user_id uuid not null unique references auth.users(id) on delete cascade,
  seat smallint not null check (seat in (0,1)),
  primary key (couple_id,user_id),
  unique (couple_id,seat)
);
create index if not exists onlyus_couple_members_user_idx on public.onlyus_couple_members(user_id);
alter table public.onlyus_couples enable row level security;
alter table public.onlyus_couple_members enable row level security;
revoke all on public.onlyus_couples,public.onlyus_couple_members from anon,authenticated;

create table if not exists public.onlyus_couple_messages (
  id bigint generated always as identity primary key,
  couple_id uuid not null references public.onlyus_couples(id) on delete cascade,
  player_id uuid not null references auth.users(id) on delete cascade,
  body text not null check (char_length(body) between 1 and 1000),
  created_at timestamptz not null default now()
);
create index if not exists onlyus_couple_messages_history_idx on public.onlyus_couple_messages(couple_id,id desc);
alter table public.onlyus_couple_messages enable row level security;
revoke all on public.onlyus_couple_messages from anon,authenticated;

create or replace function public.onlyus_is_couple_member(p_couple uuid)
returns boolean language sql stable security definer set search_path=public,auth as $$
  select exists(select 1 from public.onlyus_couple_members where couple_id=p_couple and user_id=auth.uid())
$$;
revoke all on function public.onlyus_is_couple_member(uuid) from public,anon;
grant execute on function public.onlyus_is_couple_member(uuid) to authenticated;

create or replace function public.onlyus_save_profile(p_name text,p_avatar text)
returns jsonb language plpgsql security definer set search_path=public,auth as $$
declare display_text text;
begin
  if auth.uid() is null then raise exception 'Sign in first'; end if;
  display_text=left(trim(coalesce(p_name,'')),24);
  if char_length(display_text)<1 then raise exception 'Enter your name'; end if;
  insert into public.onlyus_profiles(user_id,display_name,avatar)
  values(auth.uid(),display_text,left(coalesce(p_avatar,'💗'),16))
  on conflict(user_id) do update set display_name=excluded.display_name,avatar=excluded.avatar,updated_at=now();
  update public.onlyus_players set name=display_text,avatar=left(coalesce(p_avatar,'💗'),16) where user_id=auth.uid();
  return jsonb_build_object('user_id',auth.uid(),'display_name',display_text,'avatar',left(coalesce(p_avatar,'💗'),16));
end $$;

create or replace function public.onlyus_get_couple()
returns jsonb language plpgsql security definer set search_path=public,auth as $$
declare c uuid; partner uuid; partner_name text; partner_avatar text;
begin
  select couple_id into c from public.onlyus_couple_members where user_id=auth.uid();
  if c is null then return null; end if;
  select m.user_id into partner from public.onlyus_couple_members m where m.couple_id=c and m.user_id<>auth.uid();
  select display_name,avatar into partner_name,partner_avatar from public.onlyus_profiles where user_id=partner;
  return jsonb_build_object('id',c,'partner_id',partner,'partner_name',coalesce(partner_name,'Your person'),'partner_avatar',coalesce(partner_avatar,'💗'),
    'partner_last_seen',(select last_seen_at from public.onlyus_profiles where user_id=partner));
end $$;

create or replace function public.onlyus_touch_profile()
returns timestamptz language plpgsql security definer set search_path=public,auth as $$
declare touched timestamptz;
begin
  update public.onlyus_profiles set last_seen_at=now() where user_id=auth.uid() returning last_seen_at into touched;
  return touched;
end $$;

create or replace function public.onlyus_list_couple_messages(p_couple uuid)
returns jsonb language plpgsql security definer set search_path=public,auth as $$
begin
  if not public.onlyus_is_couple_member(p_couple) then raise exception 'Unauthorized couple membership'; end if;
  return (select coalesce(jsonb_agg(to_jsonb(m) order by m.id),'[]'::jsonb)
    from (select id,player_id,body,created_at from public.onlyus_couple_messages
      where couple_id=p_couple order by id desc limit 300) m);
end $$;

create or replace function public.onlyus_send_couple_message(p_couple uuid,p_body text)
returns jsonb language plpgsql security definer set search_path=public,auth as $$
declare body_text text; sent public.onlyus_couple_messages%rowtype;
begin
  if not public.onlyus_is_couple_member(p_couple) then raise exception 'Unauthorized couple membership'; end if;
  body_text=trim(coalesce(p_body,''));
  if char_length(body_text)<1 or char_length(body_text)>1000 then raise exception 'Messages must be between 1 and 1000 characters'; end if;
  insert into public.onlyus_couple_messages(couple_id,player_id,body) values(p_couple,auth.uid(),body_text) returning * into sent;
  return to_jsonb(sent);
end $$;

-- Keep the existing game chat and the account chat as one shared conversation.
create or replace function public.onlyus_list_messages(p_code text)
returns jsonb language plpgsql security definer set search_path=public,auth as $$
declare c uuid;
begin
  if not public.onlyus_is_member(p_code) then raise exception 'Unauthorized room membership'; end if;
  select cm.couple_id into c from public.onlyus_couple_members cm
    join public.onlyus_players p on p.user_id=cm.user_id where p.room_code=p_code and p.user_id=auth.uid();
  if c is not null then return public.onlyus_list_couple_messages(c); end if;
  return (select coalesce(jsonb_agg(to_jsonb(m) order by m.id),'[]'::jsonb)
    from (select id,player_id,body,created_at from public.onlyus_messages where room_code=p_code order by id desc limit 100) m);
end $$;

create or replace function public.onlyus_send_message(p_code text,p_body text)
returns jsonb language plpgsql security definer set search_path=public,auth as $$
declare body_text text; c uuid; sent public.onlyus_messages%rowtype;
begin
  if not public.onlyus_is_member(p_code) then raise exception 'Unauthorized room membership'; end if;
  body_text=trim(coalesce(p_body,''));
  if char_length(body_text)<1 or char_length(body_text)>1000 then raise exception 'Messages must be between 1 and 1000 characters'; end if;
  if not exists(select 1 from public.onlyus_rooms where code=p_code and expires_at>now() and status<>'finished') then raise exception 'Room is not active'; end if;
  insert into public.onlyus_messages(room_code,player_id,body) values(p_code,auth.uid(),body_text) returning * into sent;
  select couple_id into c from public.onlyus_couple_members where user_id=auth.uid();
  if c is not null then insert into public.onlyus_couple_messages(couple_id,player_id,body,created_at) values(c,auth.uid(),body_text,sent.created_at); end if;
  return to_jsonb(sent);
end $$;

-- A successful game-room join pairs the two signed-in profiles once. A user already paired
-- with someone else cannot accidentally expose their private conversation to a new account.
create or replace function public.onlyus_join_room(p_code text,p_name text,p_avatar text)
returns jsonb language plpgsql security definer set search_path=public,auth as $$
declare r public.onlyus_rooms%rowtype; n integer; first_user uuid; first_couple uuid; second_couple uuid; new_couple uuid;
begin
  if auth.uid() is null then raise exception 'Sign in to join a room'; end if;
  select * into r from public.onlyus_rooms where code=p_code for update;
  if not found then raise exception 'Invalid room code'; end if;
  if r.expires_at<now() then raise exception 'Room expired'; end if;
  if r.status<>'lobby' then raise exception 'Room already started'; end if;
  if exists(select 1 from public.onlyus_players where room_code=p_code and user_id=auth.uid()) then return public.onlyus_get_state(p_code); end if;
  select count(*) into n from public.onlyus_players where room_code=p_code;
  select user_id into first_user from public.onlyus_players where room_code=p_code and seat=0;
  if n>=2 then raise exception 'Room full: two players only'; end if;
  insert into public.onlyus_profiles(user_id,display_name,avatar)
    values(auth.uid(),left(trim(p_name),24),left(p_avatar,16))
    on conflict(user_id) do update set display_name=excluded.display_name,avatar=excluded.avatar,updated_at=now();
  insert into public.onlyus_players(room_code,user_id,seat,name,avatar) values(p_code,auth.uid(),n,left(trim(p_name),24),left(p_avatar,16));
  if n=1 then
    select couple_id into first_couple from public.onlyus_couple_members where user_id=first_user;
    select couple_id into second_couple from public.onlyus_couple_members where user_id=auth.uid();
    if first_couple is not null and second_couple is null then
      raise exception 'One player is already linked to another profile';
    elsif second_couple is not null and first_couple is null then
      raise exception 'One player is already linked to another profile';
    elsif first_couple is not null and second_couple is not null and first_couple<>second_couple then
      raise exception 'These profiles are already linked to different partners';
    elsif first_couple is null and second_couple is null then
      insert into public.onlyus_couples default values returning id into new_couple;
      insert into public.onlyus_couple_members(couple_id,user_id,seat) values(new_couple,first_user,0),(new_couple,auth.uid(),1);
      -- Bring messages from this first room into the lasting conversation.
      insert into public.onlyus_couple_messages(couple_id,player_id,body,created_at)
        select new_couple,player_id,body,created_at from public.onlyus_messages where room_code=p_code order by id;
    end if;
  end if;
  return public.onlyus_get_state(p_code);
end $$;

revoke all on function public.onlyus_save_profile(text,text),public.onlyus_get_couple(),
  public.onlyus_touch_profile(),public.onlyus_list_couple_messages(uuid),public.onlyus_send_couple_message(uuid,text),
  public.onlyus_join_room(text,text,text),public.onlyus_list_messages(text),
  public.onlyus_send_message(text,text) from public,anon;
grant execute on function public.onlyus_save_profile(text,text),public.onlyus_get_couple(),
  public.onlyus_touch_profile(),public.onlyus_list_couple_messages(uuid),public.onlyus_send_couple_message(uuid,text),
  public.onlyus_join_room(text,text,text),public.onlyus_list_messages(text),
  public.onlyus_send_message(text,text) to authenticated;

drop policy if exists "only couple members read realtime messages" on realtime.messages;
create policy "only couple members read realtime messages" on realtime.messages for select to authenticated
using ((case when split_part(realtime.topic(),':',1)='couple' then public.onlyus_is_couple_member(nullif(split_part(realtime.topic(),':',2),'')::uuid) else false end)
  or (split_part(realtime.topic(),':',1)='room' and public.onlyus_is_member(split_part(realtime.topic(),':',2))));
drop policy if exists "only couple members send realtime messages" on realtime.messages;
create policy "only couple members send realtime messages" on realtime.messages for insert to authenticated
with check ((case when split_part(realtime.topic(),':',1)='couple' then public.onlyus_is_couple_member(nullif(split_part(realtime.topic(),':',2),'')::uuid) else false end)
  or (split_part(realtime.topic(),':',1)='room' and public.onlyus_is_member(split_part(realtime.topic(),':',2))));
