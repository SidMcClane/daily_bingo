-- Dev Daily Bingo – Räume, Zugriffsstufen (global + pro Raum) und Aufteilung
-- Plattform-Admin / Raum-Admin. Siehe konzept.md, Abschnitte "Räume",
-- "Zugang: Freigabe, Kick und Sperre" und "Datenmodell" für den Hintergrund.
--
-- Baut auf 20260916120000_initial_schema.sql auf. Alles hier war zum Zeitpunkt
-- der ersten Migration noch nicht bekannt (Räume-Konzept kam erst danach).

-- ============================================================
-- profiles: is_admin -> is_platform_admin, neues status-Feld
-- ============================================================
alter table public.profiles rename column is_admin to is_platform_admin;

alter table public.profiles
  add column status text not null default 'pending'
  check (status in ('pending', 'approved', 'blocked'));

-- Alte Selbstschutz-Konstruktion ersetzen: Die ursprüngliche Version hätte
-- auch einen manuellen Admin-Bootstrap per SQL-Editor rückgängig gemacht,
-- weil sie jede Änderung an is_admin unconditional zurückgedreht hat – auch
-- die des Betreibers selbst. Neu: Nur eingreifen, wenn die Änderung über eine
-- echte Nutzer-Session läuft (auth.uid() gesetzt); direkte Änderungen durch
-- den Betreiber im SQL-Editor/CLI (kein JWT-Kontext, auth.uid() ist dort NULL)
-- bleiben unangetastet.
drop trigger if exists profiles_protect_is_admin on public.profiles;
drop function if exists public.prevent_is_admin_self_escalation();

create or replace function public.prevent_profile_privilege_escalation()
returns trigger
language plpgsql
as $$
begin
  if auth.uid() is null then
    return new;
  end if;
  if new.is_platform_admin is distinct from old.is_platform_admin then
    new.is_platform_admin := old.is_platform_admin;
  end if;
  if new.status is distinct from old.status then
    new.status := old.status;
  end if;
  return new;
end;
$$;

create trigger profiles_protect_privileges
  before update on public.profiles
  for each row
  execute function public.prevent_profile_privilege_escalation();

-- is_admin() -> is_platform_admin(), plus neues is_approved()
-- (das alte is_admin() selbst wird erst ganz am Ende der Migration
-- gedroppt, sobald keine Policy mehr darauf verweist)
create or replace function public.is_platform_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce((select is_platform_admin from public.profiles where id = auth.uid()), false);
$$;

create or replace function public.is_approved()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce((select status = 'approved' from public.profiles where id = auth.uid()), false);
$$;

-- Sichtbarkeit von Profilen: jeder sieht sich selbst (auch als pending/blocked,
-- sonst könnte die App den eigenen Wartestatus nicht anzeigen), Plattform-Admin
-- sieht alle (Freigabe-Warteschlange), sonst nur andere bereits freigegebene Profile.
drop policy if exists "profiles: select all" on public.profiles;

create policy "profiles: select self, admin, or approved others"
  on public.profiles for select
  to authenticated
  using (
    id = auth.uid()
    or public.is_platform_admin()
    or (public.is_approved() and status = 'approved')
  );

-- ============================================================
-- rooms – ein Datensatz pro Raum (Team oder Event, technisch identisch)
-- ============================================================
create table public.rooms (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(name) between 1 and 60),
  description text check (description is null or char_length(description) <= 300),
  visibility text not null default 'open' check (visibility in ('open', 'protected', 'unlisted')),
  join_code text check (join_code is null or char_length(join_code) between 4 and 20),
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now()
);

-- Fest verdrahteter erster Raum (kleinerer erster Schritt laut Konzept: ein
-- Raum reicht, bevor Lobby und Beitrittslogik gebaut werden). Feste UUID, damit
-- spätere Migrationen/Seeds ihn zuverlässig referenzieren können.
insert into public.rooms (id, name, description, visibility, created_by)
values (
  '00000000-0000-0000-0000-000000000001',
  'Hauptraum',
  'Erster, fest verdrahteter Raum – Lobby und Mehrfach-Räume folgen später.',
  'open',
  null
)
on conflict (id) do nothing;

-- ============================================================
-- room_members – Mitgliedschaft, Rolle und Status pro Raum
-- ============================================================
create table public.room_members (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null references public.rooms(id) on delete cascade,
  profile_id uuid not null references public.profiles(id) on delete cascade,
  role text not null default 'member' check (role in ('member', 'room_admin')),
  status text not null default 'active' check (status in ('pending', 'active', 'banned')),
  joined_at timestamptz not null default now(),
  unique (room_id, profile_id)
);

create index room_members_room_id_idx on public.room_members(room_id);
create index room_members_profile_id_idx on public.room_members(profile_id);

-- ============================================================
-- Helper-Funktionen für Raum-Zugriff (SECURITY DEFINER gegen RLS-Rekursion
-- auf room_members – siehe Fallstrick-Hinweis im Konzept)
-- ============================================================
create or replace function public.is_room_member(target_room uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.room_members
    where room_id = target_room
      and profile_id = auth.uid()
      and status = 'active'
  );
$$;

create or replace function public.is_room_admin(target_room uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.room_members
    where room_id = target_room
      and profile_id = auth.uid()
      and status = 'active'
      and role = 'room_admin'
  );
$$;

-- Lesezugriff: Mitglied des Raums ODER Plattform-Admin (globale Übersicht)
create or replace function public.can_view_room(target_room uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.is_room_member(target_room) or public.is_platform_admin();
$$;

-- ============================================================
-- rooms: RLS
-- ============================================================
alter table public.rooms enable row level security;

create policy "rooms: select visible or member or platform admin"
  on public.rooms for select
  to authenticated
  using (
    public.is_approved()
    and (
      visibility <> 'unlisted'
      or public.is_room_member(id)
      or public.is_platform_admin()
    )
  );

create policy "rooms: platform admin insert"
  on public.rooms for insert
  to authenticated
  with check (public.is_platform_admin());

create policy "rooms: platform admin update"
  on public.rooms for update
  to authenticated
  using (public.is_platform_admin())
  with check (public.is_platform_admin());

create policy "rooms: platform admin delete"
  on public.rooms for delete
  to authenticated
  using (public.is_platform_admin());

-- Nicht gelistete/geschützte Räume per Code finden, ohne die SELECT-Policy
-- aufzuweichen (die soll unlisted-Räume für Nicht-Mitglieder gerade verbergen).
create or replace function public.find_room_by_code(code text)
returns public.rooms
language sql
stable
security definer
set search_path = public
as $$
  select * from public.rooms where join_code = code limit 1;
$$;

-- Beitritt per Code direkt als aktives Mitglied (umgeht die einfache
-- Insert-Policy unten, die nur für offene Räume direkt auf "active" geht).
create or replace function public.join_room_with_code(target_room uuid, code text)
returns public.room_members
language plpgsql
security definer
set search_path = public
as $$
declare
  result public.room_members;
begin
  if not public.is_approved() then
    raise exception 'Account ist noch nicht global freigegeben.';
  end if;
  if not exists (
    select 1 from public.rooms where id = target_room and join_code = code
  ) then
    raise exception 'Ungültiger Beitrittscode.';
  end if;

  insert into public.room_members (room_id, profile_id, role, status)
  values (target_room, auth.uid(), 'member', 'active')
  on conflict (room_id, profile_id) do update set status = 'active'
  returning * into result;

  return result;
end;
$$;

-- ============================================================
-- room_members: RLS
-- ============================================================
alter table public.room_members enable row level security;

create policy "room_members: select own, same room, or platform admin"
  on public.room_members for select
  to authenticated
  using (
    profile_id = auth.uid()
    or public.is_room_member(room_id)
    or public.is_platform_admin()
  );

-- Direktbeitritt (aktiv) nur für offene Räume; alles andere landet als
-- Anfrage (pending) – Beitritt per Code läuft stattdessen über
-- join_room_with_code() oben.
create policy "room_members: self join open or request elsewhere"
  on public.room_members for insert
  to authenticated
  with check (
    profile_id = auth.uid()
    and public.is_approved()
    and role = 'member'
    and (
      (status = 'active' and exists (
        select 1 from public.rooms r where r.id = room_id and r.visibility = 'open'
      ))
      or status = 'pending'
    )
  );

create policy "room_members: room or platform admin manages"
  on public.room_members for update
  to authenticated
  using (public.is_room_admin(room_id) or public.is_platform_admin())
  with check (public.is_room_admin(room_id) or public.is_platform_admin());

create policy "room_members: leave own or admin removes"
  on public.room_members for delete
  to authenticated
  using (
    profile_id = auth.uid()
    or public.is_room_admin(room_id)
    or public.is_platform_admin()
  );

-- ============================================================
-- Neues Profil + Mitgliedschaft im Hauptraum automatisch bei erstem Login
-- (Trigger auf auth.users, Standard-Supabase-Muster)
-- ============================================================
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, nickname)
  values (
    new.id,
    coalesce(
      new.raw_user_meta_data->>'user_name',
      new.raw_user_meta_data->>'preferred_username',
      'user_' || substr(new.id::text, 1, 8)
    )
  )
  on conflict (id) do nothing;

  -- Kleinerer erster Schritt laut Konzept: jeder neue Nutzer landet direkt
  -- im fest verdrahteten Hauptraum, solange es noch keine Lobby gibt.
  insert into public.room_members (room_id, profile_id, role, status)
  values ('00000000-0000-0000-0000-000000000001', new.id, 'member', 'active')
  on conflict (room_id, profile_id) do nothing;

  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row
  execute function public.handle_new_user();

-- ============================================================
-- rounds: room_id ergänzen, Policies auf Raum-Mitgliedschaft umstellen
-- ============================================================
alter table public.rounds add column room_id uuid references public.rooms(id) on delete cascade;
update public.rounds set room_id = '00000000-0000-0000-0000-000000000001' where room_id is null;
alter table public.rounds alter column room_id set not null;
create index rounds_room_id_idx on public.rounds(room_id);

drop policy if exists "rounds: select all" on public.rounds;
drop policy if exists "rounds: admin write" on public.rounds;

create policy "rounds: select room members or platform admin"
  on public.rounds for select
  to authenticated
  using (public.is_approved() and public.can_view_room(room_id));

create policy "rounds: room admin write"
  on public.rounds for all
  to authenticated
  using (public.is_room_admin(room_id))
  with check (public.is_room_admin(room_id));

-- ============================================================
-- wins: room_id ergänzen, Policies umstellen
-- ============================================================
alter table public.wins add column room_id uuid references public.rooms(id) on delete cascade;
update public.wins set room_id = '00000000-0000-0000-0000-000000000001' where room_id is null;
alter table public.wins alter column room_id set not null;
create index wins_room_id_idx on public.wins(room_id);

drop policy if exists "wins: select all" on public.wins;
drop policy if exists "wins: insert own" on public.wins;

create policy "wins: select room members or platform admin"
  on public.wins for select
  to authenticated
  using (public.is_approved() and public.can_view_room(room_id));

create policy "wins: insert own within room"
  on public.wins for insert
  to authenticated
  with check (
    profile_id = auth.uid()
    and public.is_approved()
    and public.is_room_member(room_id)
  );

-- ============================================================
-- word_pool: room_id ergänzen, Policies umstellen
-- ============================================================
alter table public.word_pool add column room_id uuid references public.rooms(id) on delete cascade;
update public.word_pool set room_id = '00000000-0000-0000-0000-000000000001' where room_id is null;
alter table public.word_pool alter column room_id set not null;
create index word_pool_room_id_idx on public.word_pool(room_id);

-- Die alte globale Eindeutigkeit ("ein Wort nur einmal im gesamten Pool")
-- passt nicht mehr zu getrennten Wortlisten pro Raum.
alter table public.word_pool drop constraint if exists word_pool_word_key;
alter table public.word_pool add constraint word_pool_room_word_key unique (room_id, word);

drop policy if exists "word_pool: select all" on public.word_pool;
drop policy if exists "word_pool: insert own suggestion" on public.word_pool;
drop policy if exists "word_pool: admin status change" on public.word_pool;

create policy "word_pool: select room members or platform admin"
  on public.word_pool for select
  to authenticated
  using (public.is_approved() and public.can_view_room(room_id));

create policy "word_pool: insert own suggestion in room"
  on public.word_pool for insert
  to authenticated
  with check (
    suggested_by = auth.uid()
    and public.is_approved()
    and public.is_room_member(room_id)
  );

create policy "word_pool: room admin status change"
  on public.word_pool for update
  to authenticated
  using (public.is_room_admin(room_id))
  with check (public.is_room_admin(room_id));

-- ============================================================
-- word_votes: Policies auf Raum-Mitgliedschaft umstellen (Raumbezug über
-- word_pool.room_id, keine eigene room_id-Spalte nötig)
-- ============================================================
drop policy if exists "word_votes: select all" on public.word_votes;
drop policy if exists "word_votes: insert own" on public.word_votes;

create policy "word_votes: select room members or platform admin"
  on public.word_votes for select
  to authenticated
  using (
    public.is_approved()
    and exists (
      select 1 from public.word_pool wp
      where wp.id = word_id and public.can_view_room(wp.room_id)
    )
  );

create policy "word_votes: insert own in room"
  on public.word_votes for insert
  to authenticated
  with check (
    profile_id = auth.uid()
    and public.is_approved()
    and exists (
      select 1 from public.word_pool wp
      where wp.id = word_id and public.is_room_member(wp.room_id)
    )
  );

-- "word_votes: delete own" bleibt unverändert bestehen.

-- ============================================================
-- mode_votes: room_id ergänzen, Policies umstellen
-- ============================================================
alter table public.mode_votes add column room_id uuid references public.rooms(id) on delete cascade;
update public.mode_votes set room_id = '00000000-0000-0000-0000-000000000001' where room_id is null;
alter table public.mode_votes alter column room_id set not null;
create index mode_votes_room_id_idx on public.mode_votes(room_id);

drop policy if exists "mode_votes: select all" on public.mode_votes;
drop policy if exists "mode_votes: insert own" on public.mode_votes;
drop policy if exists "mode_votes: admin status change" on public.mode_votes;

create policy "mode_votes: select room members or platform admin"
  on public.mode_votes for select
  to authenticated
  using (public.is_approved() and public.can_view_room(room_id));

create policy "mode_votes: insert own in room"
  on public.mode_votes for insert
  to authenticated
  with check (
    started_by = auth.uid()
    and public.is_approved()
    and public.is_room_member(room_id)
  );

create policy "mode_votes: room admin status change"
  on public.mode_votes for update
  to authenticated
  using (public.is_room_admin(room_id))
  with check (public.is_room_admin(room_id));

-- Jetzt hängt keine Policy mehr an der alten globalen is_admin()-Funktion.
drop function if exists public.is_admin();

-- ============================================================
-- mode_vote_choices: Policies auf Raum-Mitgliedschaft umstellen (Raumbezug
-- über mode_votes.room_id, keine eigene room_id-Spalte nötig)
-- ============================================================
drop policy if exists "mode_vote_choices: select all" on public.mode_vote_choices;
drop policy if exists "mode_vote_choices: insert own" on public.mode_vote_choices;

create policy "mode_vote_choices: select room members or platform admin"
  on public.mode_vote_choices for select
  to authenticated
  using (
    public.is_approved()
    and exists (
      select 1 from public.mode_votes mv
      where mv.id = mode_vote_id and public.can_view_room(mv.room_id)
    )
  );

create policy "mode_vote_choices: insert own in room"
  on public.mode_vote_choices for insert
  to authenticated
  with check (
    profile_id = auth.uid()
    and public.is_approved()
    and exists (
      select 1 from public.mode_votes mv
      where mv.id = mode_vote_id and public.is_room_member(mv.room_id)
    )
  );

-- ============================================================
-- marks – gesetzte Markierungen pro Spieler und Runde (Basis für die
-- Liste der bereits gerufenen Wörter; Raumbezug über rounds.room_id)
-- ============================================================
create table public.marks (
  id uuid primary key default gen_random_uuid(),
  round_id uuid not null references public.rounds(id) on delete cascade,
  profile_id uuid not null references public.profiles(id) on delete cascade,
  word text not null check (char_length(word) between 1 and 60),
  created_at timestamptz not null default now(),
  unique (round_id, profile_id, word)
);

create index marks_round_id_idx on public.marks(round_id);

alter table public.marks enable row level security;

create policy "marks: select room members or platform admin"
  on public.marks for select
  to authenticated
  using (
    public.is_approved()
    and exists (
      select 1 from public.rounds r where r.id = round_id and public.can_view_room(r.room_id)
    )
  );

create policy "marks: insert own"
  on public.marks for insert
  to authenticated
  with check (
    profile_id = auth.uid()
    and public.is_approved()
    and exists (
      select 1 from public.rounds r where r.id = round_id and public.is_room_member(r.room_id)
    )
  );

create policy "marks: delete own"
  on public.marks for delete
  to authenticated
  using (profile_id = auth.uid());
