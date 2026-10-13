-- Let each active player author the Truth or Dare prompt their partner receives.
create or replace function public.onlyus_submit_prompt(p_code text,p_kind text,p_text text)
returns jsonb language plpgsql security definer set search_path=public,auth as $$
declare r public.onlyus_rooms%rowtype; my_index integer; body text;
begin
 if not public.onlyus_is_member(p_code) then raise exception 'Unauthorized room membership'; end if;
 if p_kind is null or p_kind not in ('truth','dare') then raise exception 'Choose Truth or Dare'; end if;
 body=trim(coalesce(p_text,''));
 if char_length(body)<1 or char_length(body)>500 then raise exception 'Your prompt must be between 1 and 500 characters'; end if;
 select * into r from public.onlyus_rooms where code=p_code for update;
 select seat into my_index from public.onlyus_players where room_code=p_code and user_id=auth.uid();
 if not found or r.status<>'playing' or r.expires_at<now() then raise exception 'Room is not active'; end if;
 if r.prompt_text is not null or r.turn_index<>my_index then raise exception 'It is not your turn to write a prompt'; end if;
 update public.onlyus_rooms
 set category='all',prompt_kind=p_kind,prompt_id='custom-'||gen_random_uuid()::text,
     prompt_text=body,prompt_category='Your prompt',prompt_player=1-my_index,
     prompt_response=null,prompt_done=false
 where code=p_code;
 return public.onlyus_get_state(p_code);
end $$;

revoke all on function public.onlyus_submit_prompt(text,text,text) from public,anon;
grant execute on function public.onlyus_submit_prompt(text,text,text) to authenticated;
