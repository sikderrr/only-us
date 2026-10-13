-- Add a server-authoritative two-player Ludo game to existing private rooms.
alter table public.onlyus_rooms add column if not exists ludo_state jsonb not null default '{"tokens":[[-1,-1,-1,-1],[-1,-1,-1,-1]],"dice":null,"last_move":null,"winner":null}'::jsonb;
alter table public.onlyus_rooms drop constraint if exists onlyus_rooms_game_mode_check;
alter table public.onlyus_rooms add constraint onlyus_rooms_game_mode_check check (game_mode in ('truth_or_dare','this_or_that','ludo'));

create or replace function public.onlyus_get_state(p_code text)
returns jsonb language plpgsql security definer set search_path=public,auth as $$
declare r public.onlyus_rooms%rowtype; answer_count integer;
begin
 if not public.onlyus_is_member(p_code) then raise exception 'Unauthorized room membership'; end if;
 select * into r from public.onlyus_rooms where code=p_code;
 if not found or r.expires_at<now() then raise exception 'Room expired'; end if;
 select count(*) into answer_count from public.onlyus_this_that_answers where room_code=p_code and round_number=r.round and user_id in (select user_id from public.onlyus_players where room_code=p_code);
 return jsonb_build_object(
   'room_code',r.code,'status',r.status,
   'players',(select coalesce(jsonb_agg(jsonb_build_object('id',p.user_id,'name',p.name,'avatar',p.avatar,'ready',p.ready,'connected',true,'last_seen_at',p.last_seen_at) order by p.seat),'[]'::jsonb) from public.onlyus_players p where p.room_code=p_code),
   'turn_index',r.turn_index,'round',r.round,'scores',r.scores,'category',r.category,
   'prompt_kind',r.prompt_kind,'prompt_id',r.prompt_id,'prompt_text',r.prompt_text,'prompt_category',r.prompt_category,'prompt_player',r.prompt_player,
   'prompt_response',r.prompt_response,'prompt_done',r.prompt_done,'recent_ids',r.recent_ids,
   'game_mode',r.game_mode,'round_limit',r.round_limit,'this_that_category',r.this_that_category,
   'this_or_that',case when r.game_mode='this_or_that' then jsonb_build_object(
     'question_id',r.this_that_question_id,'question',r.this_that_question,'option_a',r.this_that_option_a,'option_b',r.this_that_option_b,
     'category',case when r.this_that_category='all' then (select q.category from public.onlyus_this_that_questions q where q.id=r.this_that_question_id) else r.this_that_category end,
     'revealed',answer_count=2,'submitted',exists(select 1 from public.onlyus_this_that_answers a where a.room_code=p_code and a.round_number=r.round and a.user_id=auth.uid()),
     'answers',case when answer_count=2 then (select jsonb_agg(jsonb_build_object('seat',p.seat,'choice',a.choice) order by p.seat) from public.onlyus_this_that_answers a join public.onlyus_players p on p.room_code=a.room_code and p.user_id=a.user_id where a.room_code=p_code and a.round_number=r.round) else null end,
     'matched',case when answer_count=2 then (select count(distinct a.choice)=1 from public.onlyus_this_that_answers a where a.room_code=p_code and a.round_number=r.round) else null end
   ) else null end,
   'ludo_state',case when r.game_mode='ludo' then r.ludo_state else null end
 );
end $$;

create or replace function public.onlyus_configure_game(p_code text,p_game text,p_round_limit integer,p_category text)
returns jsonb language plpgsql security definer set search_path=public,auth as $$
declare r public.onlyus_rooms%rowtype; seat_no integer; q public.onlyus_this_that_questions%rowtype;
begin
 if not public.onlyus_is_member(p_code) then raise exception 'Unauthorized room membership'; end if;
 if p_game is null or p_game not in ('truth_or_dare','this_or_that','ludo') then raise exception 'Choose a valid game'; end if;
 if p_round_limit is null or p_round_limit not in (5,10,20) then raise exception 'Choose 5, 10 or 20 rounds'; end if;
 if p_category is null or p_category not in ('all','Romantic','Funny','Random') then raise exception 'Choose a valid category'; end if;
 select * into r from public.onlyus_rooms where code=p_code for update;
 select seat into seat_no from public.onlyus_players where room_code=p_code and user_id=auth.uid();
 if seat_no is distinct from 0 then raise exception 'Only the room host can choose the game'; end if;
 if r.status<>'lobby' or r.expires_at<now() then raise exception 'The room is not waiting for players'; end if;
 if (select count(*) from public.onlyus_players where room_code=p_code)<1 then raise exception 'Room creator must be present'; end if;
 delete from public.onlyus_this_that_answers where room_code=p_code;
 if p_game='this_or_that' then
   select * into q from public.onlyus_this_that_questions where p_category='all' or category=p_category order by random() limit 1;
   if not found then raise exception 'No This or That questions are available'; end if;
   update public.onlyus_rooms set game_mode=p_game,round_limit=p_round_limit,this_that_category=p_category,this_that_question_id=q.id,this_that_question=q.question,this_that_option_a=q.option_a,this_that_option_b=q.option_b,this_that_recent_ids=array[q.id],round=1,turn_index=0,scores=array[0,0],ludo_state='{"tokens":[[-1,-1,-1,-1],[-1,-1,-1,-1]],"dice":null,"last_move":null,"winner":null}'::jsonb where code=p_code;
 else
   update public.onlyus_rooms set game_mode=p_game,round_limit=p_round_limit,this_that_category='all',this_that_question_id=null,this_that_question=null,this_that_option_a=null,this_that_option_b=null,this_that_recent_ids='{}',round=1,turn_index=0,scores=array[0,0],ludo_state='{"tokens":[[-1,-1,-1,-1],[-1,-1,-1,-1]],"dice":null,"last_move":null,"winner":null}'::jsonb where code=p_code;
 end if;
 return public.onlyus_get_state(p_code);
end $$;

create or replace function public.onlyus_ludo_roll(p_code text)
returns jsonb language plpgsql security definer set search_path=public,auth,extensions as $$
declare r public.onlyus_rooms%rowtype; seat_no integer; dice integer; piece integer; progress integer; can_move boolean:=false; s jsonb;
begin
 if not public.onlyus_is_member(p_code) then raise exception 'Unauthorized room membership'; end if;
 select * into r from public.onlyus_rooms where code=p_code for update;
 select seat into seat_no from public.onlyus_players where room_code=p_code and user_id=auth.uid();
 if r.status<>'playing' or r.game_mode<>'ludo' then raise exception 'Ludo is not active'; end if;
 if seat_no is distinct from r.turn_index then raise exception 'Wait for your turn'; end if;
 s:=r.ludo_state;
 if s->>'winner' is not null then raise exception 'The game is finished'; end if;
 if s->'dice' is not null and s->'dice'<>'null'::jsonb then raise exception 'Move the rolled token first'; end if;
 dice:=get_byte(extensions.gen_random_bytes(1),0)%6+1;
 for piece in 0..3 loop
   progress:=(s->'tokens'->seat_no->>piece)::integer;
   if (progress=-1 and dice=6) or (progress>=0 and progress+dice<=57) then can_move:=true; end if;
 end loop;
 if not can_move then
   s:=jsonb_set(s,'{last_move}',jsonb_build_object('seat',seat_no,'roll',dice,'piece',null,'no_moves',true),true);
   update public.onlyus_rooms set ludo_state=s,turn_index=case when dice=6 then seat_no else 1-seat_no end,round=case when dice=6 then round else round+1 end where code=p_code;
 else
   s:=jsonb_set(s,'{dice}',to_jsonb(dice),true);
   s:=jsonb_set(s,'{last_move}','null'::jsonb,true);
   update public.onlyus_rooms set ludo_state=s where code=p_code;
 end if;
 return public.onlyus_get_state(p_code);
end $$;

create or replace function public.onlyus_ludo_move(p_code text,p_piece integer)
returns jsonb language plpgsql security definer set search_path=public,auth as $$
declare r public.onlyus_rooms%rowtype; seat_no integer; other_seat integer; dice integer; from_progress integer; to_progress integer; absolute_square integer; other_piece integer; other_progress integer; captured integer[]:='{}'; s jsonb; finished boolean:=true; won boolean:=false;
begin
 if not public.onlyus_is_member(p_code) then raise exception 'Unauthorized room membership'; end if;
 if p_piece is null or p_piece<0 or p_piece>3 then raise exception 'Invalid token'; end if;
 select * into r from public.onlyus_rooms where code=p_code for update;
 select seat into seat_no from public.onlyus_players where room_code=p_code and user_id=auth.uid();
 if r.status<>'playing' or r.game_mode<>'ludo' then raise exception 'Ludo is not active'; end if;
 if seat_no is distinct from r.turn_index then raise exception 'Wait for your turn'; end if;
 s:=r.ludo_state;
 if s->'dice' is null or s->'dice'='null'::jsonb then raise exception 'Roll the dice first'; end if;
 dice:=(s->>'dice')::integer; from_progress:=(s->'tokens'->seat_no->>p_piece)::integer;
 if from_progress=-1 then if dice<>6 then raise exception 'Roll a six to leave home'; end if; to_progress:=0;
 else to_progress:=from_progress+dice; if to_progress>57 then raise exception 'Roll the exact number to finish'; end if; end if;
 s:=jsonb_set(s,array['tokens',seat_no::text,p_piece::text],to_jsonb(to_progress),false);
 other_seat:=1-seat_no; absolute_square:=(seat_no*26+to_progress)%52;
 if to_progress<52 and absolute_square not in (0,8,13,21,26,34,39,47) then
   for other_piece in 0..3 loop
     other_progress:=(s->'tokens'->other_seat->>other_piece)::integer;
     if other_progress>=0 and other_progress<52 and (other_seat*26+other_progress)%52=absolute_square then
       s:=jsonb_set(s,array['tokens',other_seat::text,other_piece::text],to_jsonb(-1),false); captured:=array_append(captured,other_piece+1);
     end if;
   end loop;
 end if;
 for other_piece in 0..3 loop if (s->'tokens'->seat_no->>other_piece)::integer<>57 then finished:=false; end if; end loop;
 if finished then won:=true; end if;
 s:=jsonb_set(s,'{dice}','null'::jsonb,true);
 s:=jsonb_set(s,'{last_move}',jsonb_build_object('seat',seat_no,'roll',dice,'piece',p_piece,'from',from_progress,'to',to_progress,'captured',captured,'no_moves',false,'winner',case when won then seat_no else null end),true);
 if won then
   s:=jsonb_set(s,'{winner}',to_jsonb(seat_no),true);
   update public.onlyus_rooms set ludo_state=s,status='finished',scores=case when seat_no=0 then array[1,0] else array[0,1] end where code=p_code;
 else
   update public.onlyus_rooms set ludo_state=s,turn_index=case when dice=6 or cardinality(captured)>0 then seat_no else other_seat end,round=case when dice=6 or cardinality(captured)>0 then round else round+1 end where code=p_code;
 end if;
 return public.onlyus_get_state(p_code);
end $$;

revoke all on function public.onlyus_get_state(text),public.onlyus_configure_game(text,text,integer,text),public.onlyus_ludo_roll(text),public.onlyus_ludo_move(text,integer) from public,anon;
grant execute on function public.onlyus_get_state(text),public.onlyus_configure_game(text,text,integer,text),public.onlyus_ludo_roll(text),public.onlyus_ludo_move(text,integer) to authenticated;
create or replace function public.onlyus_rematch(p_code text)
returns jsonb language plpgsql security definer set search_path=public,auth as $$
declare r public.onlyus_rooms%rowtype; next_mode text;
begin
 if not public.onlyus_is_member(p_code) then raise exception 'Unauthorized room membership'; end if;
 select * into r from public.onlyus_rooms where code=p_code for update;
 if r.status<>'finished' then raise exception 'The game is not finished'; end if;
 next_mode:=case when r.game_mode='ludo' then 'ludo' else 'truth_or_dare' end;
 update public.onlyus_rooms set status='lobby',turn_index=0,round=1,scores=array[0,0],game_mode=next_mode,
   round_limit=case when next_mode='ludo' then r.round_limit else 10 end,this_that_category='all',prompt_kind=null,
   prompt_id=null,prompt_text=null,prompt_category=null,prompt_player=null,prompt_response=null,prompt_done=false,
   recent_ids='{}',this_that_question_id=null,this_that_question=null,this_that_option_a=null,this_that_option_b=null,
   this_that_recent_ids='{}',ludo_state='{"tokens":[[-1,-1,-1,-1],[-1,-1,-1,-1]],"dice":null,"last_move":null,"winner":null}'::jsonb,
   expires_at=now()+interval '24 hours' where code=p_code;
 delete from public.onlyus_this_that_answers where room_code=p_code;
 update public.onlyus_players set ready=false where room_code=p_code;
 return public.onlyus_get_state(p_code);
end $$;
revoke all on function public.onlyus_rematch(text) from public,anon;
grant execute on function public.onlyus_rematch(text) to authenticated;
