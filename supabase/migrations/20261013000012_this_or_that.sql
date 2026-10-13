-- This or That: a second game mode that reuses the existing private two-player rooms.
alter table public.onlyus_rooms
  add column if not exists game_mode text not null default 'truth_or_dare',
  add column if not exists round_limit smallint not null default 10,
  add column if not exists this_that_category text not null default 'all',
  add column if not exists this_that_question_id text,
  add column if not exists this_that_question text,
  add column if not exists this_that_option_a text,
  add column if not exists this_that_option_b text,
  add column if not exists this_that_recent_ids text[] not null default '{}';

alter table public.onlyus_rooms drop constraint if exists onlyus_rooms_game_mode_check;
alter table public.onlyus_rooms add constraint onlyus_rooms_game_mode_check
  check (game_mode in ('truth_or_dare','this_or_that'));
alter table public.onlyus_rooms drop constraint if exists onlyus_rooms_round_limit_check;
alter table public.onlyus_rooms add constraint onlyus_rooms_round_limit_check
  check (round_limit in (5,10,20));
alter table public.onlyus_rooms drop constraint if exists onlyus_rooms_this_that_category_check;
alter table public.onlyus_rooms add constraint onlyus_rooms_this_that_category_check
  check (this_that_category in ('all','Romantic','Funny','Random'));

create table if not exists public.onlyus_this_that_questions (
  id text primary key,
  category text not null check (category in ('Romantic','Funny','Random')),
  question text not null check (char_length(question) between 1 and 180),
  option_a text not null check (char_length(option_a) between 1 and 100),
  option_b text not null check (char_length(option_b) between 1 and 100)
);
alter table public.onlyus_this_that_questions enable row level security;
revoke all on public.onlyus_this_that_questions from anon,authenticated;

-- The answer table is intentionally inaccessible to browser roles. Only the
-- membership-checked RPCs below can write it, and the state RPC hides choices
-- until both members of the room have locked in.
create table if not exists public.onlyus_this_that_answers (
  room_code text not null references public.onlyus_rooms(code) on delete cascade,
  round_number integer not null check (round_number between 1 and 20),
  user_id uuid not null references auth.users(id) on delete cascade,
  choice text not null check (choice in ('A','B')),
  created_at timestamptz not null default now(),
  primary key (room_code,round_number,user_id)
);
create index if not exists onlyus_this_that_answers_room_round_idx
  on public.onlyus_this_that_answers(room_code,round_number);
alter table public.onlyus_this_that_answers enable row level security;
revoke all on public.onlyus_this_that_answers from anon,authenticated;

-- Prompt catalog rows are generated from src/thisOrThatCatalog.ts.
insert into public.onlyus_this_that_questions(id,category,question,option_a,option_b) values
  ('romantic-1','Romantic','What makes a day together feel special?','A slow morning','A late-night adventure'),
  ('romantic-2','Romantic','Pick our perfect date night','Cook something together','Dress up and go somewhere new'),
  ('romantic-3','Romantic','How should we celebrate a little win?','A cozy call','A surprise voice note'),
  ('romantic-4','Romantic','Which kind of affection feels sweetest?','Words that stay with you','Thoughtful little actions'),
  ('romantic-5','Romantic','Choose our couple tradition','Sunday check-ins','A playlist for every season'),
  ('romantic-6','Romantic','What would you keep from a perfect date?','One lovely photo','A tiny souvenir'),
  ('romantic-7','Romantic','Which message would brighten your day?','A good-morning note','A good-night voice memo'),
  ('romantic-8','Romantic','Pick a dreamy weekend together','A cabin and blankets','A seaside town stroll'),
  ('romantic-9','Romantic','How would you plan a reunion?','A favorite meal waiting','A handwritten welcome note'),
  ('romantic-10','Romantic','Which feels more romantic?','Dancing in the kitchen','Watching the stars'),
  ('romantic-11','Romantic','Pick a little love language moment','A sincere compliment','A remembered favorite snack'),
  ('romantic-12','Romantic','What would you put in a care package?','A letter and photos','Cozy socks and treats'),
  ('romantic-13','Romantic','Choose our shared playlist mood','Soft acoustic songs','Big sing-along hits'),
  ('romantic-14','Romantic','What is the best kind of surprise?','A planned date','A tiny everyday treat'),
  ('romantic-15','Romantic','Pick our ideal slow afternoon','Read side by side','Make something together'),
  ('romantic-16','Romantic','Which keeps us closest while apart?','A video call','A long thoughtful text'),
  ('romantic-17','Romantic','What should our next celebration include?','A homemade dessert','A scenic walk'),
  ('romantic-18','Romantic','Which tiny detail would you notice?','A favorite color remembered','A familiar song shared'),
  ('romantic-19','Romantic','Pick a romantic movie setting','Rainy window and tea','Golden-hour picnic'),
  ('romantic-20','Romantic','What would make a reunion extra sweet?','A long hug','A silly happy dance'),
  ('romantic-21','Romantic','Which would you save for later?','A playlist made for you','A letter to open someday'),
  ('romantic-22','Romantic','Choose our matching keepsake','Tiny matching charms','A shared photo album'),
  ('romantic-23','Romantic','What would you rather hear?','I’m proud of you','I’m lucky to know you'),
  ('romantic-24','Romantic','Pick a date we can do anywhere','Question game over a call','Make the same recipe together'),
  ('romantic-25','Romantic','Which feels like home?','Your laugh on a call','A message waiting for me'),
  ('romantic-26','Romantic','What should our dream trip include?','A quiet mountain town','A sunny beach escape'),
  ('romantic-27','Romantic','Choose a sweet way to say hello','A surprise call','A photo of your day'),
  ('romantic-28','Romantic','Which couple ritual sounds best?','Share one good thing nightly','Trade a song each week'),
  ('romantic-29','Romantic','Pick a memory to make','Our first sunrise call','Our first silly cooking attempt'),
  ('romantic-30','Romantic','What would you frame?','A favorite candid photo','A map of places we’ll go'),
  ('romantic-31','Romantic','Which is more your style?','A planned romantic evening','An unplanned little adventure'),
  ('romantic-32','Romantic','Choose our cozy-night essential','Warm drinks','A comfort movie'),
  ('romantic-33','Romantic','How should we mark a monthly milestone?','A heartfelt message','A mini virtual date'),
  ('romantic-34','Romantic','Which gift would feel more personal?','A custom playlist','A note in your handwriting'),
  ('romantic-35','Romantic','Pick a dream home detail','A reading nook for two','A kitchen for shared recipes'),
  ('romantic-36','Romantic','What makes a compliment unforgettable?','It is specific and sincere','It arrives when least expected'),
  ('romantic-37','Romantic','Choose a long-distance date idea','Watch the same sunset','Play a little online game'),
  ('romantic-38','Romantic','Which tiny gesture says “I know you”?','Remembering your favorite song','Saving you the last treat'),
  ('romantic-39','Romantic','Which future plan sounds cozier?','A quiet night in','A day exploring a new place'),
  ('romantic-40','Romantic','What would you want more of?','Little daily updates','Long catch-up conversations'),
  ('romantic-41','Romantic','Pick our ideal anniversary mood','Elegant dinner at home','A playful day out'),
  ('romantic-42','Romantic','Which would you treasure on a busy day?','A caring check-in','A funny memory from us'),
  ('romantic-43','Romantic','Choose our shared comfort','A familiar bedtime call','A favorite photo nearby'),
  ('romantic-44','Romantic','What is more romantic to you?','Being listened to closely','Being remembered in small ways'),
  ('romantic-45','Romantic','Pick a note for the future','Open on a hard day','Open on a happy day'),
  ('funny-1','Funny','Who would survive longer in a pillow-fort kingdom?','The excellent planner','The snack-hoarding champion'),
  ('funny-2','Funny','Pick our silly couple superpower','Finding lost socks','Knowing what the other wants to eat'),
  ('funny-3','Funny','Which would make the better team name?','The Waffle Wizards','The Couch Comets'),
  ('funny-4','Funny','Our imaginary pet should be…','A tiny dragon','A dramatic penguin'),
  ('funny-5','Funny','Who would laugh first during a serious speech?','Me, absolutely','You, and then me too'),
  ('funny-6','Funny','Choose our ridiculous cooking show title','Two Aprons, One Plan','A Pinch of Chaos'),
  ('funny-7','Funny','Which costume duo should we wear?','Two matching clouds','Detective and suspicious cat'),
  ('funny-8','Funny','Our mascot should do what?','Wiggle when we score','Give dramatic side-eye'),
  ('funny-9','Funny','What would our robot assistant be bad at?','Whispering','Following a recipe'),
  ('funny-10','Funny','Choose a silly award for us','Most likely to send a meme','Best team snack selection'),
  ('funny-11','Funny','Who gets lost first in a furniture store?','The map reader','The person following a dog'),
  ('funny-12','Funny','What should our secret handshake end with?','A tiny spin','A dramatic finger-gun'),
  ('funny-13','Funny','Our fictional band name is…','The Sleepy Strawberries','The Dancing Dumplings'),
  ('funny-14','Funny','Which would be our worst shared job?','Professional quiet judges','Competitive nap coaches'),
  ('funny-15','Funny','Who would win a staring contest?','The stubborn one','The one trying not to laugh'),
  ('funny-16','Funny','Pick our imaginary restaurant','Soup for the Moon','Pancakes at Midnight'),
  ('funny-17','Funny','Which would be funnier to narrate?','Making a sandwich','Searching for the TV remote'),
  ('funny-18','Funny','Our matching T-shirts should say…','Snack Department','Mildly Dramatic Duo'),
  ('funny-19','Funny','Who would be the first to talk to a houseplant?','The plant enthusiast','The person asking it for advice'),
  ('funny-20','Funny','Choose our silly entrance music','A tiny trumpet fanfare','A dramatic movie theme'),
  ('funny-21','Funny','Which challenge sounds more chaotic?','Draw each other with eyes closed','Describe a banana like a poet'),
  ('funny-22','Funny','What should our imaginary yacht be called?','The Floating Toast','The Slightly Damp Heart'),
  ('funny-23','Funny','Which would our pet teach us?','How to nap anywhere','How to demand snacks politely'),
  ('funny-24','Funny','Who would accidentally wave at a stranger?','The friendly one','The one who thought they knew them'),
  ('funny-25','Funny','Our couple emoji combo should be…','🥐🚀','🦆💌'),
  ('funny-26','Funny','Which silly competition would we enter?','Speed-folding blankets','Best made-up dance move'),
  ('funny-27','Funny','Pick a very important household title','Chief Blanket Engineer','Director of Snack Affairs'),
  ('funny-28','Funny','Who would laugh at their own joke first?','The pun maker','The person pretending not to'),
  ('funny-29','Funny','What would our cartoon theme song mention?','A missing left shoe','A heroic cup of tea'),
  ('funny-30','Funny','Choose a very odd date activity','Rate clouds like judges','Give dramatic names to pigeons'),
  ('funny-31','Funny','Which kitchen mishap is more likely?','A spoon disappears mysteriously','The timer gets a standing ovation'),
  ('funny-32','Funny','Who would be the better alien ambassador?','The polite one','The one offering snacks'),
  ('funny-33','Funny','Our fictional holiday should celebrate…','National Cozy Socks Day','International Extra Dessert Day'),
  ('funny-34','Funny','Which silly pet name wins?','Captain Wiggles','Professor Noodle'),
  ('funny-35','Funny','What should our imaginary island be made of?','Pancakes','Soft pillows'),
  ('funny-36','Funny','Who would make a better weather reporter?','The one with dramatic forecasts','The one blaming the clouds'),
  ('funny-37','Funny','Choose our emergency dance move','The confused jellyfish','The enthusiastic windshield wiper'),
  ('funny-38','Funny','Which would we put on a trophy?','Excellent Togetherness','Remarkable Snack Diplomacy'),
  ('funny-39','Funny','Who would accidentally start a sing-along?','The humming one','The person who knows every chorus'),
  ('funny-40','Funny','Our matching hats should look like…','Tiny strawberries','Sleepy little moons'),
  ('funny-41','Funny','What would our imaginary podcast discuss?','Very serious toast rankings','Why naps feel so powerful'),
  ('funny-42','Funny','Which would be our mascot’s catchphrase?','Be nice, bring snacks','We meant to do that'),
  ('funny-43','Funny','Who would take longer to choose a movie?','The list maker','The trailer re-watcher'),
  ('funny-44','Funny','Pick our couple parade float','A giant rolling cupcake','A cloud with tiny feet'),
  ('funny-45','Funny','Which is our most believable talent?','Synchronized laughing','Finding the comfiest seat'),
  ('random-1','Random','Pick a perfect drink for today','Iced lemonade','Warm cocoa'),
  ('random-2','Random','Which view would you choose?','Snow falling softly','Waves on a sunny day'),
  ('random-3','Random','Choose a tiny superpower','Always find the right song','Make plants grow happily'),
  ('random-4','Random','What would you explore first?','A hidden bookshop','A quiet garden'),
  ('random-5','Random','Pick a color for a magical door','Lavender','Coral'),
  ('random-6','Random','Which sound is more relaxing?','Rain on a roof','Leaves in a breeze'),
  ('random-7','Random','Choose a sky to watch','Bright stars','Soft sunset clouds'),
  ('random-8','Random','Which little adventure sounds nice?','A train to somewhere new','A walk with no destination'),
  ('random-9','Random','Pick a perfect breakfast','Fruit and pancakes','Toast and a favorite drink'),
  ('random-10','Random','What would you keep in a tiny time capsule?','A ticket from a fun day','A note to future you'),
  ('random-11','Random','Choose a cozy reading spot','A sunny window seat','A shady garden bench'),
  ('random-12','Random','Which weather fits your mood?','Cool and cloudy','Bright and breezy'),
  ('random-13','Random','Pick a new hobby to try','Watercolor painting','Learning a simple song'),
  ('random-14','Random','Which place would you visit?','A quiet museum','A lively night market'),
  ('random-15','Random','Choose a magical companion','A wise little owl','A friendly fox'),
  ('random-16','Random','What would you plant first?','A pot of herbs','A patch of wildflowers'),
  ('random-17','Random','Pick a perfect sound track','Gentle piano','Upbeat guitar'),
  ('random-18','Random','Which treat sounds better?','A flaky pastry','A bowl of fresh berries'),
  ('random-19','Random','Choose a way to travel','A scenic train','A little sailboat'),
  ('random-20','Random','Which tiny collection would you start?','Interesting postcards','Pretty smooth stones'),
  ('random-21','Random','Pick a favorite kind of sky','Pink clouds','Deep blue after rain'),
  ('random-22','Random','What would you learn for fun?','A few magic tricks','A new language greeting'),
  ('random-23','Random','Choose a place to pause','A library corner','A quiet cafe table'),
  ('random-24','Random','Which fictional world would you visit?','A friendly wizard village','A garden on the moon'),
  ('random-25','Random','Pick a simple weekend plan','Bake something new','Visit somewhere green'),
  ('random-26','Random','What would you put on a playlist?','Songs for a road trip','Songs for a rainy day'),
  ('random-27','Random','Choose a little object to find','A four-leaf clover','A tiny seashell'),
  ('random-28','Random','Which art would you make?','A colorful collage','A small clay figure'),
  ('random-29','Random','Pick a nighttime ritual','Write one good thing down','Look for a constellation'),
  ('random-30','Random','What would you rather discover?','A secret garden path','A new favorite song'),
  ('random-31','Random','Choose a perfect picnic extra','Fresh peaches','A crunchy snack mix'),
  ('random-32','Random','Which scent feels nicer?','Freshly baked bread','Rain on warm pavement'),
  ('random-33','Random','Pick a tiny travel souvenir','A local postcard','A handmade bookmark'),
  ('random-34','Random','What would your dream treehouse have?','A reading hammock','A telescope nook'),
  ('random-35','Random','Choose a favorite kind of morning','Quiet and misty','Bright and full of birds'),
  ('random-36','Random','Which activity would you try once?','Pottery on a wheel','Flying a kite'),
  ('random-37','Random','Pick a small daily luxury','A perfectly ripe mango','A very comfortable chair'),
  ('random-38','Random','What would you put in a wish jar?','Places to explore','Skills to learn'),
  ('random-39','Random','Choose a room with a view','Mountains far away','A garden just outside'),
  ('random-40','Random','Which keepsake sounds nicest?','A tiny pressed flower','A printed photo strip'),
  ('random-41','Random','Pick a new flavor to try','Honey lavender','Mango chili'),
  ('random-42','Random','What would you do with a free hour?','Listen to an album','Take a slow walk'),
  ('random-43','Random','Choose a pocket-sized adventure','Find a mural nearby','Try a new snack'),
  ('random-44','Random','Which would you rather make?','A paper airplane fleet','A miniature cardboard house'),
  ('random-45','Random','Pick a gentle way to reset','Stretch by a window','Step outside for fresh air')
on conflict(id) do update set category=excluded.category,question=excluded.question,option_a=excluded.option_a,option_b=excluded.option_b;

create or replace function public.onlyus_get_state(p_code text)
returns jsonb language plpgsql security definer set search_path=public,auth as $$
declare r public.onlyus_rooms%rowtype; answer_count integer;
begin
 if not public.onlyus_is_member(p_code) then raise exception 'Unauthorized room membership'; end if;
 select * into r from public.onlyus_rooms where code=p_code;
 if not found or r.expires_at<now() then raise exception 'Room expired'; end if;
 select count(*) into answer_count from public.onlyus_this_that_answers
   where room_code=p_code and round_number=r.round and user_id in
     (select user_id from public.onlyus_players where room_code=p_code);
 return jsonb_build_object(
   'room_code',r.code,'status',r.status,
   'players',(select coalesce(jsonb_agg(jsonb_build_object(
     'id',p.user_id,'name',p.name,'avatar',p.avatar,'ready',p.ready,
     'connected',true,'last_seen_at',p.last_seen_at) order by p.seat),'[]'::jsonb)
     from public.onlyus_players p where p.room_code=p_code),
   'turn_index',r.turn_index,'round',r.round,'scores',r.scores,'category',r.category,
   'prompt_kind',r.prompt_kind,'prompt_id',r.prompt_id,'prompt_text',r.prompt_text,
   'prompt_category',r.prompt_category,'prompt_player',r.prompt_player,
   'prompt_response',r.prompt_response,'prompt_done',r.prompt_done,'recent_ids',r.recent_ids,
   'game_mode',r.game_mode,'round_limit',r.round_limit,'this_that_category',r.this_that_category,
   'this_or_that',case when r.game_mode='this_or_that' then jsonb_build_object(
     'question_id',r.this_that_question_id,'question',r.this_that_question,
     'option_a',r.this_that_option_a,'option_b',r.this_that_option_b,
     'category',case when r.this_that_category='all' then (select q.category from public.onlyus_this_that_questions q where q.id=r.this_that_question_id) else r.this_that_category end,
     'revealed',answer_count=2,
     'submitted',exists(select 1 from public.onlyus_this_that_answers a where a.room_code=p_code and a.round_number=r.round and a.user_id=auth.uid()),
     'answers',case when answer_count=2 then (select jsonb_agg(jsonb_build_object('seat',p.seat,'choice',a.choice) order by p.seat) from public.onlyus_this_that_answers a join public.onlyus_players p on p.room_code=a.room_code and p.user_id=a.user_id where a.room_code=p_code and a.round_number=r.round) else null end,
     'matched',case when answer_count=2 then (select count(distinct a.choice)=1 from public.onlyus_this_that_answers a where a.room_code=p_code and a.round_number=r.round) else null end
   ) else null end
 );
end $$;

create or replace function public.onlyus_configure_game(p_code text,p_game text,p_round_limit integer,p_category text)
returns jsonb language plpgsql security definer set search_path=public,auth as $$
declare r public.onlyus_rooms%rowtype; seat_no integer; q public.onlyus_this_that_questions%rowtype; recent text[];
begin
 if not public.onlyus_is_member(p_code) then raise exception 'Unauthorized room membership'; end if;
 if p_game is null or p_game not in ('truth_or_dare','this_or_that') then raise exception 'Choose a valid game'; end if;
 if p_round_limit is null or p_round_limit not in (5,10,20) then raise exception 'Choose 5, 10 or 20 rounds'; end if;
 if p_category is null or p_category not in ('all','Romantic','Funny','Random') then raise exception 'Choose a valid category'; end if;
 select * into r from public.onlyus_rooms where code=p_code for update;
 select seat into seat_no from public.onlyus_players where room_code=p_code and user_id=auth.uid();
 if seat_no<>0 then raise exception 'Only the room host can choose the game'; end if;
 if r.status<>'lobby' or r.expires_at<now() then raise exception 'The room is not waiting for players'; end if;
 if (select count(*) from public.onlyus_players where room_code=p_code)<>2 then raise exception 'Both players need to join before choosing a game'; end if;
 delete from public.onlyus_this_that_answers where room_code=p_code;
 if p_game='this_or_that' then
   select * into q from public.onlyus_this_that_questions where p_category='all' or category=p_category order by random() limit 1;
   if not found then raise exception 'No This or That questions are available'; end if;
   update public.onlyus_rooms set game_mode=p_game,round_limit=p_round_limit,this_that_category=p_category,
     this_that_question_id=q.id,this_that_question=q.question,this_that_option_a=q.option_a,
     this_that_option_b=q.option_b,this_that_recent_ids=array[q.id],round=1,scores=array[0,0]
     where code=p_code;
 else
   update public.onlyus_rooms set game_mode=p_game,round_limit=p_round_limit,this_that_category='all',
     this_that_question_id=null,this_that_question=null,this_that_option_a=null,this_that_option_b=null,
     this_that_recent_ids='{}',round=1,scores=array[0,0] where code=p_code;
 end if;
 return public.onlyus_get_state(p_code);
end $$;

create or replace function public.onlyus_this_or_that_choose(p_code text,p_round integer,p_choice text)
returns jsonb language plpgsql security definer set search_path=public,auth as $$
declare r public.onlyus_rooms%rowtype; existing text; answer_count integer; matching boolean;
begin
 if not public.onlyus_is_member(p_code) then raise exception 'Unauthorized room membership'; end if;
 if p_choice is null or p_choice not in ('A','B') then raise exception 'Choose one of the two options'; end if;
 select * into r from public.onlyus_rooms where code=p_code for update;
 if r.status<>'playing' or r.game_mode<>'this_or_that' or r.round>r.round_limit or r.this_that_question_id is null then raise exception 'This or That is not accepting answers'; end if;
 if p_round is null or p_round<>r.round then raise exception 'This round has moved on'; end if;
 select choice into existing from public.onlyus_this_that_answers where room_code=p_code and round_number=r.round and user_id=auth.uid();
 if found then
   if existing<>p_choice then raise exception 'Your answer is already locked in'; end if;
   return public.onlyus_get_state(p_code);
 end if;
 insert into public.onlyus_this_that_answers(room_code,round_number,user_id,choice) values(p_code,r.round,auth.uid(),p_choice);
 select count(*),count(distinct choice)=1 into answer_count,matching from public.onlyus_this_that_answers where room_code=p_code and round_number=r.round;
 if answer_count=2 then
   update public.onlyus_rooms set scores=array[scores[1]+case when matching then 1 else 0 end,scores[2]+case when matching then 1 else 0 end]
     where code=p_code and status='playing' and round=r.round;
 end if;
 return public.onlyus_get_state(p_code);
end $$;

create or replace function public.onlyus_this_or_that_next(p_code text,p_round integer)
returns jsonb language plpgsql security definer set search_path=public,auth as $$
declare r public.onlyus_rooms%rowtype; answer_count integer; q public.onlyus_this_that_questions%rowtype;
begin
 if not public.onlyus_is_member(p_code) then raise exception 'Unauthorized room membership'; end if;
 select * into r from public.onlyus_rooms where code=p_code for update;
 if r.game_mode<>'this_or_that' then raise exception 'This is not a This or That room'; end if;
 if p_round is null then raise exception 'Choose the current round'; end if;
 if r.status='finished' and p_round=r.round then return public.onlyus_get_state(p_code); end if;
 if p_round<r.round then return public.onlyus_get_state(p_code); end if;
 if p_round<>r.round or r.status<>'playing' then raise exception 'This round has already moved on'; end if;
 select count(*) into answer_count from public.onlyus_this_that_answers where room_code=p_code and round_number=r.round;
 if answer_count<>2 then raise exception 'Both players need to reveal their answers first'; end if;
 if r.round>=r.round_limit then
   update public.onlyus_rooms set status='finished' where code=p_code and round=p_round and status='playing';
   return public.onlyus_get_state(p_code);
 end if;
 select * into q from public.onlyus_this_that_questions
   where (r.this_that_category='all' or category=r.this_that_category)
     and not(id=any(r.this_that_recent_ids)) order by random() limit 1;
 if not found then
   select * into q from public.onlyus_this_that_questions
     where r.this_that_category='all' or category=r.this_that_category order by random() limit 1;
 end if;
 update public.onlyus_rooms set round=round+1,this_that_question_id=q.id,this_that_question=q.question,
   this_that_option_a=q.option_a,this_that_option_b=q.option_b,
   this_that_recent_ids=(array_append(this_that_recent_ids,q.id))[greatest(1,array_length(this_that_recent_ids,1)-19):array_length(this_that_recent_ids,1)+1]
   where code=p_code and round=p_round and status='playing';
 delete from public.onlyus_this_that_answers where room_code=p_code and round_number=p_round;
 return public.onlyus_get_state(p_code);
end $$;

create or replace function public.onlyus_rematch(p_code text)
returns jsonb language plpgsql security definer set search_path=public,auth as $$
begin
 if not public.onlyus_is_member(p_code) then raise exception 'Unauthorized room membership'; end if;
 update public.onlyus_rooms set status='lobby',turn_index=0,round=1,scores=array[0,0],game_mode='truth_or_dare',
   round_limit=10,this_that_category='all',prompt_kind=null,
   prompt_id=null,prompt_text=null,prompt_category=null,prompt_player=null,prompt_response=null,prompt_done=false,
   recent_ids='{}',this_that_question_id=null,this_that_question=null,this_that_option_a=null,this_that_option_b=null,
   this_that_recent_ids='{}',expires_at=now()+interval '24 hours' where code=p_code and status='finished';
 delete from public.onlyus_this_that_answers where room_code=p_code;
 update public.onlyus_players set ready=false where room_code=p_code;
 return public.onlyus_get_state(p_code);
end $$;

revoke all on public.onlyus_this_that_questions,public.onlyus_this_that_answers from public,anon,authenticated;
revoke all on function public.onlyus_configure_game(text,text,integer,text),
  public.onlyus_this_or_that_choose(text,integer,text),public.onlyus_this_or_that_next(text,integer) from public,anon;
grant execute on function public.onlyus_configure_game(text,text,integer,text),
  public.onlyus_this_or_that_choose(text,integer,text),public.onlyus_this_or_that_next(text,integer) to authenticated;
revoke all on function public.onlyus_get_state(text),public.onlyus_rematch(text) from public,anon;
grant execute on function public.onlyus_get_state(text),public.onlyus_rematch(text) to authenticated;
