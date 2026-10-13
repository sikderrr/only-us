-- Let the room creator select the game before the invitee joins.
-- The caller must still be an authenticated room member in the host seat.
create or replace function public.onlyus_configure_game(
  p_code text,
  p_game text,
  p_round_limit integer,
  p_category text
)
returns jsonb
language plpgsql
security definer
set search_path=public,auth
as $$
declare
  r public.onlyus_rooms%rowtype;
  seat_no integer;
  q public.onlyus_this_that_questions%rowtype;
begin
  if not public.onlyus_is_member(p_code) then
    raise exception 'Unauthorized room membership';
  end if;
  if p_game is null or p_game not in ('truth_or_dare','this_or_that') then
    raise exception 'Choose a valid game';
  end if;
  if p_round_limit is null or p_round_limit not in (5,10,20) then
    raise exception 'Choose 5, 10 or 20 rounds';
  end if;
  if p_category is null or p_category not in ('all','Romantic','Funny','Random') then
    raise exception 'Choose a valid category';
  end if;

  select * into r from public.onlyus_rooms where code=p_code for update;
  select seat into seat_no
    from public.onlyus_players
    where room_code=p_code and user_id=auth.uid();
  if seat_no is distinct from 0 then
    raise exception 'Only the room host can choose the game';
  end if;
  if r.status<>'lobby' or r.expires_at<now() then
    raise exception 'The room is not waiting for players';
  end if;
  -- The host creates and configures the room before sharing its code.
  if (select count(*) from public.onlyus_players where room_code=p_code)<1 then
    raise exception 'Room creator must be present';
  end if;

  delete from public.onlyus_this_that_answers where room_code=p_code;
  if p_game='this_or_that' then
    select * into q
      from public.onlyus_this_that_questions
      where p_category='all' or category=p_category
      order by random()
      limit 1;
    if not found then
      raise exception 'No This or That questions are available';
    end if;
    update public.onlyus_rooms
      set game_mode=p_game,
          round_limit=p_round_limit,
          this_that_category=p_category,
          this_that_question_id=q.id,
          this_that_question=q.question,
          this_that_option_a=q.option_a,
          this_that_option_b=q.option_b,
          this_that_recent_ids=array[q.id],
          round=1,
          scores=array[0,0]
      where code=p_code;
  else
    update public.onlyus_rooms
      set game_mode=p_game,
          round_limit=p_round_limit,
          this_that_category='all',
          this_that_question_id=null,
          this_that_question=null,
          this_that_option_a=null,
          this_that_option_b=null,
          this_that_recent_ids='{}',
          round=1,
          scores=array[0,0]
      where code=p_code;
  end if;
  return public.onlyus_get_state(p_code);
end;
$$;
