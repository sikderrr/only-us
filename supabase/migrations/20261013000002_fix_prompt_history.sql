-- Keep prompt history non-null and append safely for the first prompt in a session.
alter table public.onlyus_rooms alter column recent_ids set default '{}'::text[];
update public.onlyus_rooms set recent_ids='{}'::text[] where recent_ids is null;
alter table public.onlyus_rooms alter column recent_ids set not null;

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
       prompt_done=true,
       resolved_by=auth.uid(),
       resolved_at=now(),
       recent_ids=array_append(coalesce(recent_ids,'{}'::text[]),prompt_id)
   where code=p_code;
 else
   update public.onlyus_rooms
   set turn_index=1-turn_index,
       round=round+1,
       recent_ids=array_append(coalesce(recent_ids,'{}'::text[]),prompt_id),
       prompt_kind=null,prompt_id=null,prompt_text=null,prompt_category=null,prompt_player=null,prompt_done=false
   where code=p_code;
 end if;
 return public.onlyus_get_state(p_code);
end $$;

revoke all on function public.onlyus_resolve_prompt(text,boolean) from public,anon;
grant execute on function public.onlyus_resolve_prompt(text,boolean) to authenticated;
