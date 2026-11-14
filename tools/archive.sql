-- Digital Future: the Archive (results people choose to share; shown after review).
-- Only the video server (with the secret key) reads or writes these. The public key can't.

create table if not exists public.df_archive (
  id text primary key,
  created timestamptz not null default now(),
  kind text not null default 'video',          -- video | picture
  status text not null default 'pending',      -- pending | approved | hidden (reported) | rejected
  no text not null,                            -- the visitor's public number, from their device
  ip_hash text not null,                       -- scrambled network address, for limits only
  job text unique,
  seconds real,
  votes integer not null default 0
);
create index if not exists df_archive_status on public.df_archive (status, created desc);
create index if not exists df_archive_ip on public.df_archive (ip_hash, created);

create table if not exists public.df_archive_votes (
  item text not null references public.df_archive (id) on delete cascade,
  ip_hash text not null,
  primary key (item, ip_hash)
);
create table if not exists public.df_archive_reports (
  item text not null references public.df_archive (id) on delete cascade,
  ip_hash text not null,
  primary key (item, ip_hash)
);

alter table public.df_archive enable row level security;
alter table public.df_archive_votes enable row level security;
alter table public.df_archive_reports enable row level security;

create or replace function public.df_archive_bump(aid text)
returns integer
language sql
security definer
set search_path = public
as $$
  update public.df_archive set votes = (select count(*) from public.df_archive_votes where item = aid)
  where id = aid
  returning votes;
$$;
revoke all on function public.df_archive_bump(text) from public, anon, authenticated;

-- files: pending ones are private; approved ones are public (served through digitalfuture.technology/archive-files/)
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('archive-pending', 'archive-pending', false, 20971520, array['video/mp4', 'image/jpeg']),
       ('archive', 'archive', true, 20971520, array['video/mp4', 'image/jpeg'])
on conflict (id) do nothing;

-- ---------- moderation (13 Nov 2026 plan) ----------
alter table public.df_archive add column if not exists labels jsonb;
alter table public.df_archive add column if not exists scores jsonb;
alter table public.df_archive add column if not exists transcript text;
alter table public.df_archive add column if not exists reviews integer not null default 0;
alter table public.df_archive add column if not exists ip_raw text;         -- kept only while pending, or when held
alter table public.df_archive add column if not exists reason text;         -- why it was rejected or held
-- status now also: held (apparent illegal content, frozen), retired (dropped past the public cap)

alter table public.df_archive_reports add column if not exists why text not null default 'other';
alter table public.df_archive_reports add column if not exists created timestamptz not null default now();

create table if not exists public.df_archive_blocks (
  hash text primary key,                       -- an ip_hash or a device number
  why text,
  created timestamptz not null default now()
);
create table if not exists public.df_archive_strikes (
  ip_hash text not null,
  device text,
  why text,
  created timestamptz not null default now()
);
create index if not exists df_archive_strikes_ip on public.df_archive_strikes (ip_hash, created);
create index if not exists df_archive_strikes_dev on public.df_archive_strikes (device, created);
alter table public.df_archive_blocks enable row level security;
alter table public.df_archive_strikes enable row level security;

-- held items: private, never deleted by code (keep 1 year after a CyberTipline report, then delete by hand)
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('archive-hold', 'archive-hold', false, 20971520, array['video/mp4', 'image/jpeg'])
on conflict (id) do nothing;
