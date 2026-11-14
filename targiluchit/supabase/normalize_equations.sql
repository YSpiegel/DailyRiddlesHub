-- Preserve existing solution rows; normalize their legacy keys at comparison time.
create or replace function public.canonical_equation(k text) returns jsonb
language plpgsql immutable strict security invoker set search_path = pg_catalog, public as $$
declare i int; split_pos int; depth int := 0; op text; left_node jsonb; right_node jsonb; terms jsonb; factors jsonb;
begin
 if k ~ '^[0-9]+$' then return jsonb_build_object('kind','number','number',k); end if;
 if left(k,1) <> '(' or right(k,1) <> ')' then raise exception 'Invalid solution key'; end if;
 for i in 2..length(k)-1 loop
  if substr(k,i,1)='(' then depth:=depth+1;
  elsif substr(k,i,1)=')' then depth:=depth-1;
  elsif depth=0 and substr(k,i,1) in ('+','-','*','/') then op:=substr(k,i,1); split_pos:=i; exit; end if;
 end loop;
 if op is null then raise exception 'Invalid solution key'; end if;
 i:=split_pos;
 left_node:=public.canonical_equation(substr(k,2,i-2));
 if op='/' then
  if substr(k,i,2)<>'//' then raise exception 'Invalid solution key'; end if;
  right_node:=public.canonical_equation(substr(k,i+2,length(k)-i-2));
 else right_node:=public.canonical_equation(substr(k,i+1,length(k)-i-1)); end if;
 if op in ('+','-') then
  select jsonb_agg(term order by (term->>0)::int desc, (term->1)::text collate "C") into terms from (
   select value as term from jsonb_array_elements(case when left_node->>'kind'='sum' then left_node->'terms' else jsonb_build_array(jsonb_build_array(1,left_node)) end)
   union all
   select jsonb_build_array((value->>0)::int * case when op='-' then -1 else 1 end,value->1) from jsonb_array_elements(case when right_node->>'kind'='sum' then right_node->'terms' else jsonb_build_array(jsonb_build_array(1,right_node)) end)
  ) t;
  return jsonb_build_object('kind','sum','terms',terms);
 elsif op='*' then
  select jsonb_agg(factor order by factor::text collate "C") into factors from (
   select value as factor from jsonb_array_elements(case when left_node->>'kind'='product' then left_node->'factors' else jsonb_build_array(left_node) end)
   union all
   select value from jsonb_array_elements(case when right_node->>'kind'='product' then right_node->'factors' else jsonb_build_array(right_node) end)
  ) f;
  return jsonb_build_object('kind','product','factors',factors);
 else return jsonb_build_object('kind','divide','left',left_node,'right',right_node); end if;
end $$;
revoke all on function public.canonical_equation(text) from public, anon, authenticated;

create or replace function public.submit_solution(tree jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid:=auth.uid(); puzzle jsonb; evaluated jsonb; supplied int[]; expected int[]; name text; inserted int := 0; puzzle_day date;
begin
 if uid is null then raise exception 'Sign in required'; end if;
 if pg_column_size(tree)>4096 then raise exception 'Expression too large'; end if;
 puzzle:=public.daily_riddle(); evaluated:=public.evaluate_expression(tree); puzzle_day:=(puzzle->>'day')::date;
 select array_agg(x::int order by x::int) into supplied from jsonb_array_elements_text(evaluated->'digits') x;
 select array_agg(x::int order by x::int) into expected from jsonb_array_elements_text(puzzle->'digits') x;
 if supplied is distinct from expected or (evaluated->>'value')::numeric<>(puzzle->>'target')::numeric then raise exception 'Invalid solution'; end if;
 name:=left(coalesce(nullif(auth.jwt()->'user_metadata'->>'full_name',''), 'שחקן'),60);
 insert into public.profiles values(uid,name) on conflict(id) do update set display_name=excluded.display_name;
 perform pg_advisory_xact_lock(hashtextextended(uid::text || ':' || puzzle_day::text,0));
 if not exists(select 1 from public.solutions s where s.user_id=uid and s.day=puzzle_day and public.canonical_equation(s.solution_key)=public.canonical_equation(evaluated->>'key')) then
  insert into public.solutions(user_id,day,solution_key,expression) values(uid,puzzle_day,evaluated->>'key',evaluated->>'display') on conflict do nothing;
  get diagnostics inserted = row_count;
 end if;
 return jsonb_build_object('inserted',inserted=1,'key',evaluated->>'key','expression',evaluated->>'display');
end $$;
create or replace function public.daily_leaderboard() returns table(display_name text, score bigint, is_me boolean) language sql security definer set search_path=public as $$ select p.display_name,count(distinct public.canonical_equation(s.solution_key)) as score, s.user_id=auth.uid() from public.solutions s join public.profiles p on p.id=s.user_id where s.day=(now() at time zone 'Asia/Jerusalem')::date group by s.user_id,p.display_name order by score desc, p.display_name asc, s.user_id asc limit 100 $$;
revoke all on function public.submit_solution(jsonb), public.daily_leaderboard() from public, anon, authenticated;
grant execute on function public.daily_leaderboard() to anon, authenticated;
grant execute on function public.submit_solution(jsonb) to authenticated;
-- Abort the migration if canonicalization does not preserve these invariants or existing keys.
do $$ begin
 if public.canonical_equation('((1+2)+3)') <> public.canonical_equation('(3+(2+1))') then raise exception 'Addition normalization failed'; end if;
 if public.canonical_equation('(9-(4-3))') <> public.canonical_equation('((9-4)+3)') then raise exception 'Subtraction normalization failed'; end if;
 if public.canonical_equation('((2*3)*4)') <> public.canonical_equation('(4*(3*2))') then raise exception 'Multiplication normalization failed'; end if;
 if public.canonical_equation('(9//(4//3))') = public.canonical_equation('((9//4)//3)') then raise exception 'Division must remain ordered'; end if;
 perform public.canonical_equation(solution_key) from public.solutions;
end $$;
