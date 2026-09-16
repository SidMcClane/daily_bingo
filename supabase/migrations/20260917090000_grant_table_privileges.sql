-- Fix: RLS-Policies allein reichen nicht. Ohne einen Basis-GRANT auf
-- Tabellenebene blockt Postgres den Zugriff für die Rolle `authenticated`
-- schon *vor* jeder RLS-Prüfung (Fehler 42501 "permission denied for table").
-- Beim Tabellenanlegen über das Supabase-Dashboard passiert das automatisch,
-- bei reinen SQL-Migrationen wie unseren nicht – das wurde in den ersten
-- beiden Migrationen schlicht vergessen.

grant usage on schema public to authenticated;

grant select, insert, update, delete on
  public.profiles,
  public.rooms,
  public.room_members,
  public.rounds,
  public.wins,
  public.word_pool,
  public.word_votes,
  public.mode_votes,
  public.mode_vote_choices,
  public.marks
to authenticated;

-- Damit das bei künftigen Migrationen nicht wieder vergessen wird: neue
-- Tabellen im public-Schema bekommen die Rechte automatisch mit.
alter default privileges in schema public
  grant select, insert, update, delete on tables to authenticated;
