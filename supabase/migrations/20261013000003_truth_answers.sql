-- Keep an optional, room-visible truth answer in authoritative room state.
alter table public.onlyus_rooms
  add column if not exists prompt_response text
  check (prompt_response is null or char_length(prompt_response)<=500);

create or replace function public.onlyus_get_state(p_code text)
returns jsonb language plpgsql security definer set search_path=public,auth as $$
declare r public.onlyus_rooms%rowtype;
begin
 if not public.onlyus_is_member(p_code) then raise exception 'Unauthorized room membership'; end if;
 select * into r from public.onlyus_rooms where code=p_code;
 if not found or r.expires_at<now() then raise exception 'Room expired'; end if;
 return jsonb_build_object(
   'room_code',r.code,'status',r.status,
   'players',(select coalesce(jsonb_agg(jsonb_build_object('id',p.user_id,'name',p.name,'avatar',p.avatar,'ready',p.ready,'connected',true) order by p.seat),'[]'::jsonb) from public.onlyus_players p where p.room_code=p_code),
   'turn_index',r.turn_index,'round',r.round,'scores',r.scores,'category',r.category,
   'prompt_kind',r.prompt_kind,'prompt_id',r.prompt_id,'prompt_text',r.prompt_text,
   'prompt_category',r.prompt_category,'prompt_player',r.prompt_player,
   'prompt_response',r.prompt_response,'prompt_done',r.prompt_done,'recent_ids',r.recent_ids
 );
end $$;

create or replace function public.onlyus_take_turn(p_code text,p_kind text,p_category text)
returns jsonb language plpgsql security definer set search_path=public,auth as $$
declare r public.onlyus_rooms%rowtype; my_index integer; picked public.onlyus_prompts%rowtype;
begin
 if p_kind not in ('truth','dare') or p_category not in ('all','Cute','Romantic','Flirty','Funny','Deep') then raise exception 'Invalid prompt selection'; end if;
 if not public.onlyus_is_member(p_code) then raise exception 'Unauthorized room membership'; end if;
 select * into r from public.onlyus_rooms where code=p_code for update;
 select seat into my_index from public.onlyus_players where room_code=p_code and user_id=auth.uid();
 if r.status<>'playing' or r.prompt_text is not null or r.turn_index<>my_index then raise exception 'Not your turn'; end if;
 select * into picked from public.onlyus_prompts where kind=p_kind and (p_category='all' or category=p_category) and not(id=any(coalesce(r.recent_ids,'{}'::text[]))) order by random() limit 1;
 if not found then select * into picked from public.onlyus_prompts where kind=p_kind and (p_category='all' or category=p_category) order by random() limit 1; end if;
 if not found then raise exception 'No prompts in this category'; end if;
 update public.onlyus_rooms set category=p_category,prompt_kind=p_kind,prompt_id=picked.id,prompt_text=picked.text,prompt_category=picked.category,prompt_player=my_index,prompt_response=null,prompt_done=false where code=p_code;
 return public.onlyus_get_state(p_code);
end $$;

create or replace function public.onlyus_submit_truth(p_code text,p_response text)
returns jsonb language plpgsql security definer set search_path=public,auth as $$
declare r public.onlyus_rooms%rowtype; my_index integer; answer text;
begin
 if not public.onlyus_is_member(p_code) then raise exception 'Unauthorized room membership'; end if;
 answer=trim(coalesce(p_response,''));
 if char_length(answer)<1 or char_length(answer)>500 then raise exception 'Answer must be between 1 and 500 characters'; end if;
 select * into r from public.onlyus_rooms where code=p_code for update;
 select seat into my_index from public.onlyus_players where room_code=p_code and user_id=auth.uid();
 if r.status<>'playing' or r.prompt_kind<>'truth' or r.prompt_text is null or r.prompt_done then raise exception 'There is no active truth prompt'; end if;
 if r.prompt_player<>my_index then raise exception 'Only the player answering this truth can share it'; end if;
 if r.prompt_response is not null then raise exception 'Your truth has already been shared'; end if;
 update public.onlyus_rooms set prompt_response=answer where code=p_code;
 return public.onlyus_get_state(p_code);
end $$;

create or replace function public.onlyus_resolve_prompt(p_code text,p_done boolean)
returns jsonb language plpgsql security definer set search_path=public,auth as $$
declare r public.onlyus_rooms%rowtype;
begin
 if not public.onlyus_is_member(p_code) then raise exception 'Unauthorized room membership'; end if;
 select * into r from public.onlyus_rooms where code=p_code for update;
 if r.status<>'playing' or r.prompt_text is null or r.prompt_done then raise exception 'Prompt already resolved'; end if;
 if p_done then
   update public.onlyus_rooms
   set scores=array[ scores[1]+case when prompt_player=0 then 1 else 0 end,
                     scores[2]+case when prompt_player=1 then 1 else 0 end ],
       prompt_done=true,resolved_by=auth.uid(),resolved_at=now(),
       recent_ids=array_append(coalesce(recent_ids,'{}'::text[]),prompt_id)
   where code=p_code;
 else
   update public.onlyus_rooms
   set turn_index=1-turn_index,round=round+1,
       recent_ids=array_append(coalesce(recent_ids,'{}'::text[]),prompt_id),
       prompt_kind=null,prompt_id=null,prompt_text=null,prompt_category=null,
       prompt_player=null,prompt_response=null,prompt_done=false
   where code=p_code;
 end if;
 return public.onlyus_get_state(p_code);
end $$;

create or replace function public.onlyus_continue(p_code text)
returns jsonb language plpgsql security definer set search_path=public,auth as $$
begin
 if not public.onlyus_is_member(p_code) then raise exception 'Unauthorized room membership'; end if;
 update public.onlyus_rooms
 set turn_index=1-turn_index,round=round+1,prompt_kind=null,prompt_id=null,
     prompt_text=null,prompt_category=null,prompt_player=null,prompt_response=null,prompt_done=false
 where code=p_code and status='playing' and prompt_done=true;
 if not found then raise exception 'Prompt is not complete'; end if;
 return public.onlyus_get_state(p_code);
end $$;

create or replace function public.onlyus_rematch(p_code text)
returns jsonb language plpgsql security definer set search_path=public,auth as $$
begin
 if not public.onlyus_is_member(p_code) then raise exception 'Unauthorized room membership'; end if;
 update public.onlyus_rooms
 set status='lobby',turn_index=0,round=1,scores=array[0,0],prompt_kind=null,
     prompt_id=null,prompt_text=null,prompt_category=null,prompt_player=null,
     prompt_response=null,prompt_done=false,recent_ids='{}',expires_at=now()+interval '24 hours'
 where code=p_code and status='finished';
 update public.onlyus_players set ready=false where room_code=p_code;
 return public.onlyus_get_state(p_code);
end $$;

revoke all on function public.onlyus_get_state(text),public.onlyus_take_turn(text,text,text),
  public.onlyus_submit_truth(text,text),public.onlyus_resolve_prompt(text,boolean),
  public.onlyus_continue(text),public.onlyus_rematch(text) from public,anon;
grant execute on function public.onlyus_get_state(text),public.onlyus_take_turn(text,text,text),
  public.onlyus_submit_truth(text,text),public.onlyus_resolve_prompt(text,boolean),
  public.onlyus_continue(text),public.onlyus_rematch(text) to authenticated;
