-- One player chooses the prompt type, their partner writes the prompt, then
-- the chooser responds to it. All transitions are room locked and authoritative.
create or replace function public.onlyus_choose_kind(p_code text,p_kind text)
returns jsonb language plpgsql security definer set search_path=public,auth as $$
declare r public.onlyus_rooms%rowtype; my_index integer;
begin
 if not public.onlyus_is_member(p_code) then raise exception 'Unauthorized room membership'; end if;
 if p_kind is null or p_kind not in ('truth','dare') then raise exception 'Choose Truth or Dare'; end if;
 select * into r from public.onlyus_rooms where code=p_code for update;
 select seat into my_index from public.onlyus_players where room_code=p_code and user_id=auth.uid();
 if r.status<>'playing' or r.expires_at<now() then raise exception 'Room is not active'; end if;
 if r.turn_index<>my_index or r.prompt_kind is not null or r.prompt_text is not null then
   raise exception 'It is not your turn to choose';
 end if;
 update public.onlyus_rooms set prompt_kind=p_kind,prompt_player=my_index,
   prompt_id='custom-'||gen_random_uuid()::text,prompt_text=null,
   prompt_category='Your person’s prompt',prompt_response=null,prompt_done=false
 where code=p_code;
 return public.onlyus_get_state(p_code);
end $$;

create or replace function public.onlyus_submit_prompt(p_code text,p_kind text,p_text text)
returns jsonb language plpgsql security definer set search_path=public,auth as $$
declare r public.onlyus_rooms%rowtype; my_index integer; body text;
begin
 if not public.onlyus_is_member(p_code) then raise exception 'Unauthorized room membership'; end if;
 body=trim(coalesce(p_text,''));
 if char_length(body)<1 or char_length(body)>500 then raise exception 'Your prompt must be between 1 and 500 characters'; end if;
 select * into r from public.onlyus_rooms where code=p_code for update;
 select seat into my_index from public.onlyus_players where room_code=p_code and user_id=auth.uid();
 if r.status<>'playing' or r.expires_at<now() then raise exception 'Room is not active'; end if;
 if r.prompt_kind is distinct from p_kind or r.prompt_text is not null
    or r.prompt_player is null or my_index=r.prompt_player then
   raise exception 'Your person must choose Truth or Dare before you write a prompt';
 end if;
 update public.onlyus_rooms set prompt_text=body where code=p_code;
 return public.onlyus_get_state(p_code);
end $$;

create or replace function public.onlyus_resolve_prompt(p_code text,p_done boolean)
returns jsonb language plpgsql security definer set search_path=public,auth as $$
declare r public.onlyus_rooms%rowtype; my_index integer;
begin
 if not public.onlyus_is_member(p_code) then raise exception 'Unauthorized room membership'; end if;
 select * into r from public.onlyus_rooms where code=p_code for update;
 select seat into my_index from public.onlyus_players where room_code=p_code and user_id=auth.uid();
 if r.status<>'playing' or r.prompt_text is null or r.prompt_done then raise exception 'Prompt already resolved'; end if;
 if r.prompt_player is distinct from my_index then raise exception 'Only the player who chose this prompt can respond'; end if;
 if p_done and r.prompt_kind='truth' and r.prompt_response is null then
   raise exception 'Send your truth answer before completing this prompt';
 end if;
 if p_done then
   update public.onlyus_rooms set
     scores=array[scores[1]+case when prompt_player=0 then 1 else 0 end,
                 scores[2]+case when prompt_player=1 then 1 else 0 end],
     prompt_done=true,resolved_by=auth.uid(),resolved_at=now(),
     recent_ids=array_append(coalesce(recent_ids,'{}'::text[]),prompt_id)
   where code=p_code;
 else
   update public.onlyus_rooms set turn_index=1-turn_index,round=round+1,
     recent_ids=array_append(coalesce(recent_ids,'{}'::text[]),prompt_id),
     prompt_kind=null,prompt_id=null,prompt_text=null,prompt_category=null,
     prompt_player=null,prompt_response=null,prompt_done=false
   where code=p_code;
 end if;
 return public.onlyus_get_state(p_code);
end $$;

revoke all on function public.onlyus_choose_kind(text,text),
  public.onlyus_submit_prompt(text,text,text),
  public.onlyus_resolve_prompt(text,boolean) from public,anon;
grant execute on function public.onlyus_choose_kind(text,text),
  public.onlyus_submit_prompt(text,text,text),
  public.onlyus_resolve_prompt(text,boolean) to authenticated;
