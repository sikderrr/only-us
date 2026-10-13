-- Social profiles, friend requests, friendships, and persistent one-to-one chat.
-- Existing Only Us accounts remain valid; username is nullable until they complete setup.
alter table public.onlyus_profiles
  alter column display_name drop not null,
  add column if not exists username text;
alter table public.onlyus_profiles drop constraint if exists onlyus_profiles_display_name_check;
alter table public.onlyus_profiles add constraint onlyus_profiles_display_name_check
  check (display_name is null or char_length(display_name) between 1 and 32);
create unique index if not exists onlyus_profiles_username_lower_uidx
  on public.onlyus_profiles (lower(username)) where username is not null;
create index if not exists onlyus_profiles_username_prefix_idx
  on public.onlyus_profiles (username text_pattern_ops) where username is not null;

create table if not exists public.onlyus_friend_requests (
  id uuid primary key default gen_random_uuid(),
  sender_id uuid not null references auth.users(id) on delete cascade,
  recipient_id uuid not null references auth.users(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending','accepted','rejected','cancelled')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (sender_id <> recipient_id)
);
create unique index if not exists onlyus_one_pending_pair_request
  on public.onlyus_friend_requests (least(sender_id,recipient_id), greatest(sender_id,recipient_id))
  where status='pending';
create index if not exists onlyus_requests_inbox_idx on public.onlyus_friend_requests(recipient_id,created_at desc) where status='pending';
create index if not exists onlyus_requests_outbox_idx on public.onlyus_friend_requests(sender_id,created_at desc) where status='pending';
alter table public.onlyus_friend_requests enable row level security;
revoke all on public.onlyus_friend_requests from anon,authenticated;

create table if not exists public.onlyus_social_search_limits (
  user_id uuid primary key references auth.users(id) on delete cascade,
  searched_at timestamptz not null
);
alter table public.onlyus_social_search_limits enable row level security;
revoke all on public.onlyus_social_search_limits from anon,authenticated;

create table if not exists public.onlyus_friendships (
  user_a uuid not null references auth.users(id) on delete cascade,
  user_b uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key(user_a,user_b),
  check(user_a < user_b)
);
create index if not exists onlyus_friendships_b_idx on public.onlyus_friendships(user_b,user_a);
alter table public.onlyus_friendships enable row level security;
revoke all on public.onlyus_friendships from anon,authenticated;

create table if not exists public.onlyus_direct_conversations (
  id uuid primary key default gen_random_uuid(),
  user_a uuid not null references auth.users(id) on delete cascade,
  user_b uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check(user_a < user_b),
  unique(user_a,user_b)
);
create index if not exists onlyus_direct_conversations_b_idx on public.onlyus_direct_conversations(user_b,user_a);
alter table public.onlyus_direct_conversations enable row level security;
revoke all on public.onlyus_direct_conversations from anon,authenticated;

create table if not exists public.onlyus_direct_conversation_members (
  conversation_id uuid not null references public.onlyus_direct_conversations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  last_read_message_id bigint not null default 0,
  primary key(conversation_id,user_id)
);
create index if not exists onlyus_direct_members_user_idx on public.onlyus_direct_conversation_members(user_id,conversation_id);
alter table public.onlyus_direct_conversation_members enable row level security;
revoke all on public.onlyus_direct_conversation_members from anon,authenticated;

create table if not exists public.onlyus_direct_messages (
  id bigint generated always as identity primary key,
  conversation_id uuid not null references public.onlyus_direct_conversations(id) on delete cascade,
  sender_id uuid not null references auth.users(id) on delete cascade,
  content text not null check(char_length(content) between 1 and 2000),
  created_at timestamptz not null default now()
);
create index if not exists onlyus_direct_messages_history_idx on public.onlyus_direct_messages(conversation_id,id desc);
alter table public.onlyus_direct_messages enable row level security;
create or replace function public.onlyus_is_direct_member(p_conversation uuid)
returns boolean language sql stable security definer set search_path=public,auth as $$
  select exists(select 1 from public.onlyus_direct_conversation_members m
    join public.onlyus_direct_conversations c on c.id=m.conversation_id
    where m.conversation_id=p_conversation and m.user_id=auth.uid()
      and ((c.user_a=auth.uid() and c.user_b<>auth.uid()) or (c.user_b=auth.uid() and c.user_a<>auth.uid())))
$$;
create policy onlyus_direct_messages_member_read on public.onlyus_direct_messages for select to authenticated
  using (public.onlyus_is_direct_member(onlyus_direct_messages.conversation_id));
grant select on public.onlyus_direct_messages to authenticated;
revoke insert,update,delete,truncate,references,trigger on public.onlyus_direct_messages from anon,authenticated;

create or replace function public.onlyus_valid_username(p_username text)
returns boolean language sql immutable set search_path=public as $$
  select coalesce(lower(trim(p_username)) ~ '^[a-z][a-z0-9_]{2,19}$',false)
    and lower(trim(p_username)) <> all(array['admin','administrator','support','help','onlyus','only_us','system','moderator','null','undefined','root','official'])
$$;

create or replace function public.onlyus_check_username(p_username text)
returns jsonb language plpgsql stable security definer set search_path=public,auth as $$
declare normalized text:=lower(trim(coalesce(p_username,'')));
begin
  if not public.onlyus_valid_username(normalized) then
    return jsonb_build_object('valid',false,'available',false,'message','Use 3–20 letters, numbers or underscores. Start with a letter.');
  end if;
  return jsonb_build_object('valid',true,'available',not exists(select 1 from public.onlyus_profiles where lower(username)=normalized));
end $$;

create or replace function public.onlyus_get_my_profile()
returns jsonb language plpgsql stable security definer set search_path=public,auth as $$
declare p public.onlyus_profiles%rowtype;
begin
  if auth.uid() is null then raise exception 'Sign in first'; end if;
  select * into p from public.onlyus_profiles where user_id=auth.uid();
  if not found then return null; end if;
  return jsonb_build_object('username',p.username,'display_name',p.display_name,'avatar',p.avatar,'last_seen_at',p.last_seen_at);
end $$;

create or replace function public.onlyus_complete_profile(p_username text,p_display_name text default null,p_avatar text default '💗')
returns jsonb language plpgsql security definer set search_path=public,auth as $$
declare normalized text:=lower(trim(coalesce(p_username,''))); shown text:=left(trim(coalesce(p_display_name,'')),32); chosen_avatar text:=left(coalesce(nullif(trim(p_avatar),''),'💗'),16);
begin
  if auth.uid() is null or auth.jwt()->>'is_anonymous'='true' then raise exception 'Sign in with your account first'; end if;
  if not public.onlyus_valid_username(normalized) then raise exception 'Username must be 3–20 characters: letters, numbers or underscore, starting with a letter'; end if;
  insert into public.onlyus_profiles(user_id,username,display_name,avatar)
    values(auth.uid(),normalized,nullif(shown,''),chosen_avatar)
    on conflict(user_id) do update set username=excluded.username,display_name=excluded.display_name,avatar=excluded.avatar,updated_at=now();
  update public.onlyus_players set name=coalesce(nullif(shown,''),normalized),avatar=chosen_avatar where user_id=auth.uid();
  return public.onlyus_get_my_profile();
exception when unique_violation then raise exception 'That username is already taken. Try another one.' using errcode='23505';
end $$;

create or replace function public.onlyus_is_friend(p_user uuid,p_other uuid)
returns boolean language sql stable security definer set search_path=public,auth as $$
  select exists(select 1 from public.onlyus_friendships f where f.user_a=least(p_user,p_other) and f.user_b=greatest(p_user,p_other))
$$;
create or replace function public.onlyus_is_direct_member(p_conversation uuid)
returns boolean language sql stable security definer set search_path=public,auth as $$
  select exists(select 1 from public.onlyus_direct_conversation_members m
    join public.onlyus_direct_conversations c on c.id=m.conversation_id
    where m.conversation_id=p_conversation and m.user_id=auth.uid()
      and ((c.user_a=auth.uid() and c.user_b<>auth.uid()) or (c.user_b=auth.uid() and c.user_a<>auth.uid())))
$$;
create or replace function public.onlyus_can_access_user_topic(p_username text)
returns boolean language sql stable security definer set search_path=public,auth as $$
 select auth.uid() is not null and exists(
   select 1 from public.onlyus_profiles target
   where target.username=p_username and (
     target.user_id=auth.uid() or public.onlyus_is_friend(auth.uid(),target.user_id) or exists(
       select 1 from public.onlyus_friend_requests r where r.status='pending' and
       ((r.sender_id=auth.uid() and r.recipient_id=target.user_id) or (r.sender_id=target.user_id and r.recipient_id=auth.uid()))
     )
   )
 )
$$;

create or replace function public.onlyus_search_users(p_query text)
returns jsonb language plpgsql security definer set search_path=public,auth as $$
declare q text:=lower(trim(coalesce(p_query,''))); prior_search timestamptz;
begin
 if auth.uid() is null or auth.jwt()->>'is_anonymous'='true' then raise exception 'Sign in to discover people'; end if;
 if char_length(q)<2 then return '[]'::jsonb; end if;
 if q !~ '^[a-z][a-z0-9_]{1,19}$' then raise exception 'Search with at least two username letters, numbers or underscores'; end if;
 perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text,7903));
 select searched_at into prior_search from public.onlyus_social_search_limits where user_id=auth.uid();
 if prior_search is not null and clock_timestamp()-prior_search<interval '300 milliseconds' then raise exception 'Please wait a moment before searching again'; end if;
 insert into public.onlyus_social_search_limits(user_id,searched_at) values(auth.uid(),clock_timestamp())
   on conflict(user_id) do update set searched_at=excluded.searched_at;
 return (select coalesce(jsonb_agg(to_jsonb(x) order by x.username),'[]'::jsonb) from (
   select p.username,p.display_name,p.avatar,
     case when public.onlyus_is_friend(auth.uid(),p.user_id) then 'friends'
       when exists(select 1 from public.onlyus_friend_requests r where r.sender_id=auth.uid() and r.recipient_id=p.user_id and r.status='pending') then 'outgoing'
       when exists(select 1 from public.onlyus_friend_requests r where r.sender_id=p.user_id and r.recipient_id=auth.uid() and r.status='pending') then 'incoming' else 'none' end as relation
   from public.onlyus_profiles p where p.user_id<>auth.uid() and p.username like q||'%' order by p.username limit 20
 ) x);
end $$;

create or replace function public.onlyus_list_friend_requests()
returns jsonb language plpgsql stable security definer set search_path=public,auth as $$
begin
 if auth.uid() is null or auth.jwt()->>'is_anonymous'='true' then raise exception 'Sign in first'; end if;
 return (select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc),'[]'::jsonb) from (
   select r.id,r.status,r.created_at,(r.recipient_id=auth.uid()) as incoming,
     p.username,p.display_name,p.avatar
   from public.onlyus_friend_requests r join public.onlyus_profiles p on p.user_id=case when r.sender_id=auth.uid() then r.recipient_id else r.sender_id end
   where (r.sender_id=auth.uid() or r.recipient_id=auth.uid()) and r.status='pending'
 ) x);
end $$;

create or replace function public.onlyus_list_friends()
returns jsonb language plpgsql stable security definer set search_path=public,auth as $$
begin
 if auth.uid() is null or auth.jwt()->>'is_anonymous'='true' then raise exception 'Sign in first'; end if;
 return (select coalesce(jsonb_agg(to_jsonb(x) order by coalesce(x.display_name,x.username)),'[]'::jsonb) from (
   select p.username,p.display_name,p.avatar,p.last_seen_at
   from public.onlyus_friendships f join public.onlyus_profiles p on p.user_id=case when f.user_a=auth.uid() then f.user_b else f.user_a end
   where f.user_a=auth.uid() or f.user_b=auth.uid()
 ) x);
end $$;

create or replace function public.onlyus_friend_action(p_username text,p_action text)
returns jsonb language plpgsql security definer set search_path=public,auth as $$
declare me uuid:=auth.uid(); other_id uuid; lo uuid; hi uuid; req public.onlyus_friend_requests%rowtype;
begin
 if me is null or auth.jwt()->>'is_anonymous'='true' then raise exception 'Sign in first'; end if;
 if p_action not in ('send','accept','reject','cancel','remove') then raise exception 'Invalid friend action'; end if;
 select user_id into other_id from public.onlyus_profiles where lower(username)=lower(trim(p_username));
 if other_id is null then raise exception 'That username could not be found'; end if;
 if other_id=me then raise exception 'You cannot add yourself'; end if;
 lo:=least(me,other_id); hi:=greatest(me,other_id);
 perform pg_advisory_xact_lock(hashtextextended(lo::text||':'||hi::text,0));
 if p_action='send' then
   if public.onlyus_is_friend(me,other_id) then return jsonb_build_object('status','friends'); end if;
   select * into req from public.onlyus_friend_requests where sender_id=other_id and recipient_id=me and status='pending' order by created_at desc limit 1 for update;
   if found then return jsonb_build_object('status','incoming'); end if;
   select * into req from public.onlyus_friend_requests where sender_id=me and recipient_id=other_id and status='pending' order by created_at desc limit 1 for update;
   if found then return jsonb_build_object('status','outgoing'); end if;
   insert into public.onlyus_friend_requests(sender_id,recipient_id) values(me,other_id);
   return jsonb_build_object('status','outgoing');
 elsif p_action='accept' then
   select * into req from public.onlyus_friend_requests where sender_id=other_id and recipient_id=me and status='pending' order by created_at desc limit 1 for update;
   if not found then raise exception 'That incoming request is no longer pending'; end if;
   update public.onlyus_friend_requests set status='accepted',updated_at=now() where id=req.id;
   insert into public.onlyus_friendships(user_a,user_b) values(lo,hi) on conflict do nothing;
   return jsonb_build_object('status','friends');
 elsif p_action='reject' then
   update public.onlyus_friend_requests set status='rejected',updated_at=now() where sender_id=other_id and recipient_id=me and status='pending';
   if not found then raise exception 'That incoming request is no longer pending'; end if;
   return jsonb_build_object('status','rejected');
 elsif p_action='cancel' then
   update public.onlyus_friend_requests set status='cancelled',updated_at=now() where sender_id=me and recipient_id=other_id and status='pending';
   if not found then raise exception 'That outgoing request is no longer pending'; end if;
   return jsonb_build_object('status','cancelled');
 else
   delete from public.onlyus_friendships where user_a=lo and user_b=hi;
   if not found then raise exception 'You are not friends'; end if;
   return jsonb_build_object('status','removed');
 end if;
end $$;

create or replace function public.onlyus_get_or_create_direct_conversation(p_username text)
returns jsonb language plpgsql security definer set search_path=public,auth as $$
declare me uuid:=auth.uid(); other_id uuid; lo uuid; hi uuid; cid uuid;
begin
 if me is null then raise exception 'Sign in first'; end if;
 select user_id into other_id from public.onlyus_profiles where lower(username)=lower(trim(p_username));
 if other_id is null or other_id=me then raise exception 'User not found'; end if;
 lo:=least(me,other_id); hi:=greatest(me,other_id);
 if not public.onlyus_is_friend(me,other_id) then raise exception 'You can chat with accepted friends only'; end if;
 perform pg_advisory_xact_lock(hashtextextended(lo::text||':'||hi::text,0));
 insert into public.onlyus_direct_conversations(user_a,user_b) values(lo,hi)
 on conflict(user_a,user_b) do update set updated_at=public.onlyus_direct_conversations.updated_at returning id into cid;
 insert into public.onlyus_direct_conversation_members(conversation_id,user_id) values(cid,lo),(cid,hi) on conflict do nothing;
 return jsonb_build_object('id',cid,'username',p_username);
end $$;

create or replace function public.onlyus_list_direct_conversations()
returns jsonb language plpgsql stable security definer set search_path=public,auth as $$
begin
 if auth.uid() is null then raise exception 'Sign in first'; end if;
 return (select coalesce(jsonb_agg(to_jsonb(x) order by x.last_at desc nulls last),'[]'::jsonb) from (
   select c.id,p.username,p.display_name,p.avatar,p.last_seen_at,m.content as last_message,m.created_at as last_at,
     (select count(*) from public.onlyus_direct_messages unread where unread.conversation_id=c.id and unread.sender_id<>auth.uid() and unread.id>mine.last_read_message_id) as unread_count,
     exists(select 1 from public.onlyus_friendships f where f.user_a=least(auth.uid(),p.user_id) and f.user_b=greatest(auth.uid(),p.user_id)) as is_friend
   from public.onlyus_direct_conversation_members mine join public.onlyus_direct_conversations c on c.id=mine.conversation_id
   join public.onlyus_profiles p on p.user_id=case when c.user_a=auth.uid() then c.user_b else c.user_a end
   left join lateral (select dm.content,dm.created_at from public.onlyus_direct_messages dm where dm.conversation_id=c.id order by dm.id desc limit 1) m on true
   where mine.user_id=auth.uid()
 ) x);
end $$;

create or replace function public.onlyus_list_direct_messages(p_conversation uuid,p_before bigint default null)
returns jsonb language plpgsql security definer set search_path=public,auth as $$
declare out jsonb;
begin
 if not public.onlyus_is_direct_member(p_conversation) then raise exception 'Unauthorized conversation'; end if;
 select coalesce(jsonb_agg(to_jsonb(x) order by x.id),'[]'::jsonb) into out from (
   select id,sender_id,content,created_at from public.onlyus_direct_messages where conversation_id=p_conversation and (p_before is null or id<p_before) order by id desc limit 60
 ) x;
 if p_before is null then
   update public.onlyus_direct_conversation_members set last_read_message_id=greatest(last_read_message_id,coalesce((select max(id) from public.onlyus_direct_messages where conversation_id=p_conversation),0)) where conversation_id=p_conversation and user_id=auth.uid();
 end if;
 return out;
end $$;

create or replace function public.onlyus_send_direct_message(p_conversation uuid,p_content text)
returns jsonb language plpgsql security definer set search_path=public,auth as $$
declare body text:=trim(coalesce(p_content,'')); sent public.onlyus_direct_messages%rowtype; other_id uuid;
begin
 if not public.onlyus_is_direct_member(p_conversation) then raise exception 'Unauthorized conversation'; end if;
 if char_length(body)<1 or char_length(body)>2000 then raise exception 'Messages must be 1–2000 characters'; end if;
 select case when user_a=auth.uid() then user_b else user_a end into other_id from public.onlyus_direct_conversations where id=p_conversation;
 if not public.onlyus_is_friend(auth.uid(),other_id) then raise exception 'You can only send messages while you are friends'; end if;
 insert into public.onlyus_direct_messages(conversation_id,sender_id,content) values(p_conversation,auth.uid(),body) returning * into sent;
 update public.onlyus_direct_conversations set updated_at=sent.created_at where id=p_conversation;
 return to_jsonb(sent);
end $$;

-- Preserve the legacy linked-couple room-chat behavior only when both room seats
-- belong to that same couple. Rooms with other accepted friends stay room-scoped.
create or replace function public.onlyus_list_messages(p_code text)
returns jsonb language plpgsql security definer set search_path=public,auth as $$
declare c uuid; linked_players integer;
begin
 if not public.onlyus_is_member(p_code) then raise exception 'Unauthorized room membership'; end if;
 select cm.couple_id into c from public.onlyus_couple_members cm
   join public.onlyus_players p on p.user_id=cm.user_id
   where p.room_code=p_code and p.user_id=auth.uid();
 if c is not null then
   select count(*) into linked_players from public.onlyus_players p
     join public.onlyus_couple_members cm on cm.user_id=p.user_id and cm.couple_id=c
     where p.room_code=p_code;
   if linked_players=2 then return public.onlyus_list_couple_messages(c); end if;
 end if;
 return (select coalesce(jsonb_agg(to_jsonb(m) order by m.id),'[]'::jsonb)
   from (select id,player_id,body,created_at from public.onlyus_messages
     where room_code=p_code order by id desc limit 100) m);
end $$;

create or replace function public.onlyus_send_message(p_code text,p_body text)
returns jsonb language plpgsql security definer set search_path=public,auth as $$
declare body_text text:=trim(coalesce(p_body,'')); c uuid; linked_players integer; sent_id bigint; sent_user uuid; sent_body text; sent_at timestamptz;
begin
 if not public.onlyus_is_member(p_code) then raise exception 'Unauthorized room membership'; end if;
 if char_length(body_text)<1 or char_length(body_text)>1000 then raise exception 'Messages must be between 1 and 1000 characters'; end if;
 if not exists(select 1 from public.onlyus_rooms where code=p_code and expires_at>now() and status<>'finished') then raise exception 'Room is not active'; end if;
 select cm.couple_id into c from public.onlyus_couple_members cm
   join public.onlyus_players p on p.user_id=cm.user_id
   where p.room_code=p_code and p.user_id=auth.uid();
 if c is not null then
   select count(*) into linked_players from public.onlyus_players p
     join public.onlyus_couple_members cm on cm.user_id=p.user_id and cm.couple_id=c
     where p.room_code=p_code;
 end if;
 if c is not null and linked_players=2 then
   insert into public.onlyus_couple_messages(couple_id,player_id,body)
     values(c,auth.uid(),body_text) returning id,player_id,body,created_at into sent_id,sent_user,sent_body,sent_at;
 else
   insert into public.onlyus_messages(room_code,player_id,body)
     values(p_code,auth.uid(),body_text) returning id,player_id,body,created_at into sent_id,sent_user,sent_body,sent_at;
 end if;
 return jsonb_build_object('id',sent_id,'player_id',sent_user,'body',sent_body,'created_at',sent_at);
end $$;

-- A prior couple link must not prevent an accepted friend from joining a new game.
-- New pairs are still linked once for compatibility with the original account chat.
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
 insert into public.onlyus_players(room_code,user_id,seat,name,avatar)
   values(p_code,auth.uid(),n,left(trim(p_name),24),left(p_avatar,16));
 if n=1 then
   select couple_id into first_couple from public.onlyus_couple_members where user_id=first_user;
   select couple_id into second_couple from public.onlyus_couple_members where user_id=auth.uid();
   if first_couple is null and second_couple is null then
     insert into public.onlyus_couples default values returning id into new_couple;
     insert into public.onlyus_couple_members(couple_id,user_id,seat)
       values(new_couple,first_user,0),(new_couple,auth.uid(),1);
     insert into public.onlyus_couple_messages(couple_id,player_id,body,created_at)
       select new_couple,player_id,body,created_at from public.onlyus_messages where room_code=p_code order by id;
   end if;
 end if;
 return public.onlyus_get_state(p_code);
end $$;

create or replace function public.onlyus_is_conversation_member(p_conversation uuid)
returns boolean language sql stable security definer set search_path=public,auth as $$
  select public.onlyus_is_direct_member(p_conversation)
$$;

revoke all on function public.onlyus_valid_username(text),public.onlyus_check_username(text),public.onlyus_is_friend(uuid,uuid),public.onlyus_is_direct_member(uuid),public.onlyus_is_conversation_member(uuid),public.onlyus_can_access_user_topic(text) from public;
revoke all on function public.onlyus_get_my_profile(),public.onlyus_complete_profile(text,text,text),public.onlyus_search_users(text),public.onlyus_list_friend_requests(),public.onlyus_list_friends(),public.onlyus_friend_action(text,text),public.onlyus_get_or_create_direct_conversation(text),public.onlyus_list_direct_conversations(),public.onlyus_list_direct_messages(uuid,bigint),public.onlyus_send_direct_message(uuid,text) from public,anon;
grant execute on function public.onlyus_valid_username(text),public.onlyus_check_username(text) to anon,authenticated;
grant execute on function public.onlyus_is_friend(uuid,uuid),public.onlyus_is_direct_member(uuid),public.onlyus_is_conversation_member(uuid),public.onlyus_can_access_user_topic(text) to authenticated;
grant execute on function public.onlyus_get_my_profile(),public.onlyus_complete_profile(text,text,text),public.onlyus_search_users(text),public.onlyus_list_friend_requests(),public.onlyus_list_friends(),public.onlyus_friend_action(text,text),public.onlyus_get_or_create_direct_conversation(text),public.onlyus_list_direct_conversations(),public.onlyus_list_direct_messages(uuid,bigint),public.onlyus_send_direct_message(uuid,text) to authenticated;

drop policy if exists onlyus_social_topic_read on realtime.messages;
create policy onlyus_social_topic_read on realtime.messages for select to authenticated using (
  ((split_part(realtime.topic(),':',1)='dm' and public.onlyus_is_conversation_member(nullif(split_part(realtime.topic(),':',2),'')::uuid))
   or (split_part(realtime.topic(),':',1)='user' and public.onlyus_can_access_user_topic(split_part(realtime.topic(),':',2))))
);
drop policy if exists onlyus_social_topic_broadcast on realtime.messages;
create policy onlyus_social_topic_broadcast on realtime.messages for insert to authenticated with check (
  (split_part(realtime.topic(),':',1)='dm' and public.onlyus_is_conversation_member(nullif(split_part(realtime.topic(),':',2),'')::uuid))
  or (split_part(realtime.topic(),':',1)='user' and public.onlyus_can_access_user_topic(split_part(realtime.topic(),':',2)))
);
