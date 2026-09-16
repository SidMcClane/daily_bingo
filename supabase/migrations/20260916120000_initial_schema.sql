-- Dev Daily Bingo – initiales Datenmodell für die Multiplayer-Version
-- Siehe konzept.md, Abschnitt "Datenmodell-Entwurf" für den Hintergrund.

-- ============================================================
-- profiles – ein Datensatz pro Spieler (Supabase Auth User-ID)
-- ============================================================
create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  nickname text not null unique check (char_length(nickname) between 1 and 30),
  is_admin boolean not null default false,
  created_at timestamptz not null default now()
);

alter table public.profiles enable row level security;

create policy "profiles: select all"
  on public.profiles for select
  to authenticated
  using (true);

create policy "profiles: insert own"
  on public.profiles for insert
  to authenticated
  with check (auth.uid() = id);

create policy "profiles: update own"
  on public.profiles for update
  to authenticated
  using (auth.uid() = id)
  with check (auth.uid() = id);

-- is_admin darf nicht per normalem Update selbst gesetzt werden
-- (muss manuell im Supabase SQL-Editor oder von einem bestehenden Admin geändert werden)
create or replace function public.prevent_is_admin_self_escalation()
returns trigger
language plpgsql
as $$
begin
  if new.is_admin is distinct from old.is_admin then
    new.is_admin := old.is_admin;
  end if;
  return new;
end;
$$;

create trigger profiles_protect_is_admin
  before update on public.profiles
  for each row
  execute function public.prevent_is_admin_self_escalation();

-- ============================================================
-- Helper: is_admin() – security definer, damit Policies auf
-- profiles nicht rekursiv gegen ihre eigene RLS laufen
-- ============================================================
create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce((select is_admin from public.profiles where id = auth.uid()), false);
$$;

-- ============================================================
-- rounds – eine Zeile pro Runde (First-Blood- / One-Week-Wipe-Mode)
-- ============================================================
create table public.rounds (
  id uuid primary key default gen_random_uuid(),
  mode text not null check (mode in ('first_blood', 'one_week_wipe')),
  words jsonb not null, -- Snapshot der 25 aktiven Wörter für diese Runde
  started_at timestamptz not null default now(),
  ended_at timestamptz
);

alter table public.rounds enable row level security;

create policy "rounds: select all"
  on public.rounds for select
  to authenticated
  using (true);

create policy "rounds: admin write"
  on public.rounds for all
  to authenticated
  using (public.is_admin())
  with check (public.is_admin());

-- ============================================================
-- wins – eine Zeile pro erzieltem Bingo
-- ============================================================
create table public.wins (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.profiles(id) on delete cascade,
  round_id uuid references public.rounds(id) on delete set null,
  lines_count smallint not null default 1 check (lines_count > 0),
  achieved_at timestamptz not null default now()
);

create index wins_profile_id_idx on public.wins(profile_id);
create index wins_round_id_idx on public.wins(round_id);

alter table public.wins enable row level security;

create policy "wins: select all"
  on public.wins for select
  to authenticated
  using (true);

create policy "wins: insert own"
  on public.wins for insert
  to authenticated
  with check (profile_id = auth.uid());

-- kein update/delete: wins sind ein unveränderliches Log

-- ============================================================
-- word_pool – Vorschlags-Pool für Bingo-Wörter
-- ============================================================
create table public.word_pool (
  id uuid primary key default gen_random_uuid(),
  word text not null unique check (char_length(word) between 1 and 40),
  suggested_by uuid references public.profiles(id) on delete set null,
  status text not null default 'proposed' check (status in ('proposed', 'active', 'rejected')),
  created_at timestamptz not null default now()
);

alter table public.word_pool enable row level security;

create policy "word_pool: select all"
  on public.word_pool for select
  to authenticated
  using (true);

create policy "word_pool: insert own suggestion"
  on public.word_pool for insert
  to authenticated
  with check (suggested_by = auth.uid());

create policy "word_pool: admin status change"
  on public.word_pool for update
  to authenticated
  using (public.is_admin())
  with check (public.is_admin());

-- ============================================================
-- word_votes – eine Stimme pro Nutzer und Wort
-- ============================================================
create table public.word_votes (
  id uuid primary key default gen_random_uuid(),
  word_id uuid not null references public.word_pool(id) on delete cascade,
  profile_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  unique (word_id, profile_id)
);

create index word_votes_word_id_idx on public.word_votes(word_id);

alter table public.word_votes enable row level security;

create policy "word_votes: select all"
  on public.word_votes for select
  to authenticated
  using (true);

create policy "word_votes: insert own"
  on public.word_votes for insert
  to authenticated
  with check (profile_id = auth.uid());

create policy "word_votes: delete own"
  on public.word_votes for delete
  to authenticated
  using (profile_id = auth.uid());

-- ============================================================
-- mode_votes – Abstimmung über Moduswechsel (First-Blood <-> One-Week-Wipe)
-- ============================================================
create table public.mode_votes (
  id uuid primary key default gen_random_uuid(),
  proposed_mode text not null check (proposed_mode in ('first_blood', 'one_week_wipe')),
  started_by uuid not null references public.profiles(id) on delete cascade,
  started_at timestamptz not null default now(),
  ends_at timestamptz not null,
  status text not null default 'open' check (status in ('open', 'passed', 'rejected', 'expired'))
);

alter table public.mode_votes enable row level security;

create policy "mode_votes: select all"
  on public.mode_votes for select
  to authenticated
  using (true);

create policy "mode_votes: insert own"
  on public.mode_votes for insert
  to authenticated
  with check (started_by = auth.uid());

create policy "mode_votes: admin status change"
  on public.mode_votes for update
  to authenticated
  using (public.is_admin())
  with check (public.is_admin());

-- ============================================================
-- mode_vote_choices – eine Stimme pro Nutzer und Mode-Vote
-- ============================================================
create table public.mode_vote_choices (
  id uuid primary key default gen_random_uuid(),
  mode_vote_id uuid not null references public.mode_votes(id) on delete cascade,
  profile_id uuid not null references public.profiles(id) on delete cascade,
  choice boolean not null, -- true = dafür, false = dagegen
  created_at timestamptz not null default now(),
  unique (mode_vote_id, profile_id)
);

create index mode_vote_choices_mode_vote_id_idx on public.mode_vote_choices(mode_vote_id);

alter table public.mode_vote_choices enable row level security;

create policy "mode_vote_choices: select all"
  on public.mode_vote_choices for select
  to authenticated
  using (true);

create policy "mode_vote_choices: insert own"
  on public.mode_vote_choices for insert
  to authenticated
  with check (profile_id = auth.uid());
