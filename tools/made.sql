-- Digital Future: count of finished results (videos and pictures), shown on the page.
-- A number per day and kind, nothing else. Capped per day so a script can't run it up forever.

create table if not exists public.df_made (
  day date not null,
  kind text not null,
  n integer not null default 0,
  primary key (day, kind)
);
alter table public.df_made enable row level security;

create or replace function public.df_made(kind text default 'video')
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  k text := case when kind = 'picture' then 'picture' else 'video' end;
  d date := (now() at time zone 'America/Chicago')::date;
begin
  if coalesce((select sum(n) from public.df_made where day = d), 0) >= 5000 then return; end if;
  insert into public.df_made (day, kind, n) values (d, k, 1)
  on conflict on constraint df_made_pkey do update set n = public.df_made.n + 1;
end;
$$;

create or replace function public.df_visit_stats()
returns json
language sql
security definer
set search_path = public
stable
as $$
  select json_build_object(
    'last_30_min', coalesce((select sum(n) from public.df_visit_slots where slot > now() - interval '30 minutes'), 0),
    'today', coalesce((select sum(n) from public.df_visit_slots where slot >= date_trunc('day', now() at time zone 'America/Chicago') at time zone 'America/Chicago'), 0),
    'all_time', coalesce((select sum(n) from public.df_visit_slots), 0),
    'videos', coalesce((select sum(n) from public.df_made where kind = 'video'), 0),
    'pictures', coalesce((select sum(n) from public.df_made where kind = 'picture'), 0),
    'days', coalesce((
      select json_agg(d order by d.day desc) from (
        select (slot at time zone 'America/Chicago')::date as day, sum(n) as visits
        from public.df_visit_slots
        where slot > now() - interval '30 days'
        group by 1
      ) d), '[]'::json),
    'sources', coalesce((
      select json_agg(x order by x.visits desc) from (
        select src, sum(n) as visits
        from public.df_visit_sources
        where day > (now() at time zone 'America/Chicago')::date - 30
        group by src
      ) x), '[]'::json)
  );
$$;

revoke all on function public.df_made(text) from public;
grant execute on function public.df_made(text) to anon;
