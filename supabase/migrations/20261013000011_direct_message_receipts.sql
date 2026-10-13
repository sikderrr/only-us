-- WhatsApp-style delivery and read receipts for private friend conversations.
-- A delivery cursor means this signed-in participant's app has received the
-- conversation. A read cursor advances only while that conversation is open.
alter table public.onlyus_direct_conversation_members
  add column if not exists last_delivered_message_id bigint not null default 0;

create or replace function public.onlyus_ack_direct_message_delivery(p_conversation uuid)
returns bigint
language plpgsql
security definer
set search_path=public,auth
as $$
declare latest_id bigint;
begin
  if not public.onlyus_is_direct_member(p_conversation) then
    raise exception 'Unauthorized conversation';
  end if;

  select coalesce(max(id),0) into latest_id
    from public.onlyus_direct_messages
    where conversation_id=p_conversation;

  update public.onlyus_direct_conversation_members
    set last_delivered_message_id=greatest(last_delivered_message_id,latest_id)
    where conversation_id=p_conversation and user_id=auth.uid();

  return latest_id;
end;
$$;

create or replace function public.onlyus_mark_direct_messages_read(p_conversation uuid)
returns bigint
language plpgsql
security definer
set search_path=public,auth
as $$
declare latest_id bigint;
begin
  if not public.onlyus_is_direct_member(p_conversation) then
    raise exception 'Unauthorized conversation';
  end if;

  select coalesce(max(id),0) into latest_id
    from public.onlyus_direct_messages
    where conversation_id=p_conversation;

  update public.onlyus_direct_conversation_members
    set last_delivered_message_id=greatest(last_delivered_message_id,latest_id),
        last_read_message_id=greatest(last_read_message_id,latest_id)
    where conversation_id=p_conversation and user_id=auth.uid();

  return latest_id;
end;
$$;

create or replace function public.onlyus_list_direct_messages(p_conversation uuid,p_before bigint default null)
returns jsonb
language plpgsql
security definer
set search_path=public,auth
as $$
declare out jsonb;
begin
  if not public.onlyus_is_direct_member(p_conversation) then
    raise exception 'Unauthorized conversation';
  end if;

  select coalesce(jsonb_agg(to_jsonb(x) order by x.id),'[]'::jsonb) into out
  from (
    select m.id,m.sender_id,m.content,m.created_at,
      (m.sender_id=auth.uid() and m.id<=coalesce(peer.last_delivered_message_id,0)) as delivered,
      (m.sender_id=auth.uid() and m.id<=coalesce(peer.last_read_message_id,0)) as read
    from public.onlyus_direct_messages m
    left join public.onlyus_direct_conversation_members peer
      on peer.conversation_id=m.conversation_id and peer.user_id<>auth.uid()
    where m.conversation_id=p_conversation
      and (p_before is null or m.id<p_before)
    order by m.id desc
    limit 60
  ) x;

  return out;
end;
$$;

revoke all on function public.onlyus_ack_direct_message_delivery(uuid),
  public.onlyus_mark_direct_messages_read(uuid) from public,anon;
grant execute on function public.onlyus_ack_direct_message_delivery(uuid),
  public.onlyus_mark_direct_messages_read(uuid) to authenticated;
