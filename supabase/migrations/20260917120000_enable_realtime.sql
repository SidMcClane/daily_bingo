-- Bugfix: Realtime-Subscriptions (postgres_changes) blieben aus, weil unsere
-- per SQL-Migration angelegten Tabellen nie in die `supabase_realtime`-
-- Publikation aufgenommen wurden. Im Dashboard passiert das automatisch beim
-- Umlegen des "Realtime"-Schalters, bei reinen SQL-Migrationen nicht – gleiche
-- Kategorie Fehler wie die fehlenden Tabellen-GRANTs zuvor.
alter publication supabase_realtime add table
  public.rooms,
  public.room_members,
  public.rounds,
  public.wins,
  public.marks,
  public.word_pool,
  public.word_votes,
  public.mode_votes,
  public.mode_vote_choices;
