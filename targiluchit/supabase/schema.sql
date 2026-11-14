-- Run in a new Supabase project using the SQL editor. All dates use Jerusalem time.
create table if not exists public.riddles (day date primary key, digits int[] not null, target int not null);
create table if not exists public.solutions (user_id uuid not null references auth.users on delete cascade, day date not null references public.riddles, solution_key text not null, expression text not null, created_at timestamptz not null default now(), primary key(user_id, day, solution_key));
create table if not exists public.profiles (id uuid primary key references auth.users on delete cascade, display_name text not null);
alter table public.riddles enable row level security;
alter table public.solutions enable row level security;
alter table public.profiles enable row level security;
revoke all on public.riddles, public.solutions, public.profiles from anon, authenticated;

-- The puzzle is generated once per date, consistently for every player. No cron is needed.
create or replace function public.daily_riddle() returns jsonb language plpgsql security definer set search_path = public as $$
declare d date := (now() at time zone 'Asia/Jerusalem')::date; h text; nums int[]; result public.riddles;
begin
 h := md5('targiluchit-v2:' || d::text);
 nums := array[2+get_byte(decode(substr(h,1,2),'hex'),0)%8, 2+get_byte(decode(substr(h,3,2),'hex'),0)%8, 2+get_byte(decode(substr(h,5,2),'hex'),0)%8, 1+get_byte(decode(substr(h,7,2),'hex'),0)%9, 1+get_byte(decode(substr(h,9,2),'hex'),0)%9];
 insert into public.riddles values (d, nums, nums[1]*nums[2]*nums[3]+nums[4]+nums[5]) on conflict do nothing;
 select * into result from public.riddles where day=d;
 return jsonb_build_object('day',result.day,'digits',result.digits,'target',result.target);
end $$;

-- Evaluate a bounded expression tree on the server; never trust a submitted score.
create or replace function public.evaluate_expression(n jsonb, depth int default 0) returns jsonb language plpgsql immutable set search_path = public as $$
declare a jsonb; b jsonb; op text; v numeric; k text; disp text; ds jsonb;
begin
 if depth > 8 or jsonb_typeof(n) <> 'object' then raise exception 'Invalid expression'; end if;
 if n ? 'digit' then
  if (n->>'digit') !~ '^[1-9]$' then raise exception 'Invalid digit'; end if;
  return jsonb_build_object('value',(n->>'digit')::numeric,'key',n->>'digit','display',n->>'digit','digits',jsonb_build_array((n->>'digit')::int),'numeric',true);
 end if;
 op := n->>'op'; if op is null or op not in ('+','-','*','//','concat') then raise exception 'Invalid operator'; end if;
 a:=public.evaluate_expression(n->'left',depth+1); b:=public.evaluate_expression(n->'right',depth+1);
 ds:=(a->'digits')||(b->'digits'); if jsonb_array_length(ds)>5 then raise exception 'Too many digits'; end if;
 if op='concat' then
  if not (a->>'numeric')::boolean or not (b->>'numeric')::boolean then raise exception 'Invalid concatenation'; end if;
  k:=(a->>'key')||(b->>'key'); return jsonb_build_object('value',k::numeric,'key',k,'display',k,'digits',ds,'numeric',true);
 end if;
 if op in ('+','*') and a->>'key' > b->>'key' then a:=b; b:=public.evaluate_expression(n->'left',depth+1); end if;
 if op='+' then v:=(a->>'value')::numeric+(b->>'value')::numeric;
 elsif op='-' then v:=(a->>'value')::numeric-(b->>'value')::numeric;
 elsif op='*' then v:=(a->>'value')::numeric*(b->>'value')::numeric;
 else if (b->>'value')::numeric=0 then raise exception 'Division by zero'; end if; v:=floor((a->>'value')::numeric/(b->>'value')::numeric); end if;
 k:='('||(a->>'key')||op||(b->>'key')||')'; disp:='('||(a->>'display')||' '||case op when '*' then '×' when '-' then '−' when '//' then '÷' else '+' end||' '||(b->>'display')||')';
 return jsonb_build_object('value',v,'key',k,'display',disp,'digits',ds,'numeric',false);
end $$;
revoke all on function public.evaluate_expression(jsonb,int) from public, anon, authenticated;
create or replace function public.submit_solution(tree jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid:=auth.uid(); puzzle jsonb; evaluated jsonb; supplied int[]; expected int[]; name text; inserted int;
begin
 if uid is null then raise exception 'Sign in required'; end if;
 if pg_column_size(tree)>4096 then raise exception 'Expression too large'; end if;
 puzzle:=public.daily_riddle(); evaluated:=public.evaluate_expression(tree);
 select array_agg(x::int order by x::int) into supplied from jsonb_array_elements_text(evaluated->'digits') x;
 select array_agg(x::int order by x::int) into expected from jsonb_array_elements_text(puzzle->'digits') x;
 if supplied is distinct from expected or (evaluated->>'value')::numeric<>(puzzle->>'target')::numeric then raise exception 'Invalid solution'; end if;
 name:=left(coalesce(nullif(auth.jwt()->'user_metadata'->>'full_name',''), 'שחקן'),60);
 insert into public.profiles values(uid,name) on conflict(id) do update set display_name=excluded.display_name;
 insert into public.solutions(user_id,day,solution_key,expression) values(uid,(puzzle->>'day')::date,evaluated->>'key',evaluated->>'display') on conflict do nothing;
 get diagnostics inserted = row_count;
 return jsonb_build_object('inserted',inserted=1,'key',evaluated->>'key','expression',evaluated->>'display');
end $$;
create or replace function public.my_solutions() returns table(solution_key text, expression text) language sql security definer set search_path=public as $$ select s.solution_key,s.expression from public.solutions s where s.user_id=auth.uid() and s.day=(now() at time zone 'Asia/Jerusalem')::date order by s.created_at $$;
create or replace function public.daily_leaderboard() returns table(display_name text, score bigint, is_me boolean) language sql security definer set search_path=public as $$ select p.display_name,count(*) as score, s.user_id=auth.uid() from public.solutions s join public.profiles p on p.id=s.user_id where s.day=(now() at time zone 'Asia/Jerusalem')::date group by s.user_id,p.display_name order by score desc, p.display_name asc, s.user_id asc limit 100 $$;
revoke all on function public.daily_riddle(), public.submit_solution(jsonb), public.my_solutions(), public.daily_leaderboard() from public, anon, authenticated;
grant execute on function public.daily_riddle(), public.daily_leaderboard() to anon, authenticated;
grant execute on function public.submit_solution(jsonb), public.my_solutions() to authenticated;

create index if not exists solutions_day_idx on public.solutions(day);
