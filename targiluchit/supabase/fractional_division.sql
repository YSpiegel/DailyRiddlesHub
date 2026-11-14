-- Apply to an existing installation to update expression validation.
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
 else if (b->>'value')::numeric=0 then raise exception 'Division by zero'; end if; v:=round((a->>'value')::numeric/(b->>'value')::numeric,3); end if;
 k:='('||(a->>'key')||op||(b->>'key')||')'; disp:='('||(a->>'display')||' '||case op when '*' then '×' when '-' then '−' when '//' then '÷' else '+' end||' '||(b->>'display')||')';
 return jsonb_build_object('value',v,'key',k,'display',disp,'digits',ds,'numeric',false);
end $$;
