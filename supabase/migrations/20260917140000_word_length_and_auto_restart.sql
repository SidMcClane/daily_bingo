-- Bugfix 1: word_pool.word-Limit (40 Zeichen) war zu knapp für Wörter mit
-- Emoji/Klammer-Anmerkungen ("Let's talk about... Sexuelle Anspielungen 🎶")
-- - genau das hat den Bulk-Import mit "word_pool_word_check" abgelehnt.
alter table public.word_pool drop constraint word_pool_word_check;
alter table public.word_pool add constraint word_pool_word_check check (char_length(word) between 1 and 80);

-- marks.word übernimmt denselben Text (aus rounds.words, das wiederum aus
-- word_pool.word stammt) - Limit entsprechend mitziehen, sonst würde ein
-- längeres Wort beim Markieren scheitern.
alter table public.marks drop constraint marks_word_check;
alter table public.marks add constraint marks_word_check check (char_length(word) between 1 and 80);

-- Bugfix 2: report_win() hat die Runde IMMER beendet, unabhängig vom Modus.
-- Das ist nur für First-Blood-Mode richtig - im One-Week-Wipe-Mode sollen
-- mehrere Bingos pro Woche möglich sein, ohne dass die Runde dabei endet.
create or replace function public.report_win(target_round uuid, p_lines_count smallint)
returns public.wins
language plpgsql
security definer
set search_path = public
as $$
declare
  result public.wins;
  target_room uuid;
  round_mode text;
begin
  if not public.is_approved() then
    raise exception 'Account ist nicht global freigegeben.';
  end if;

  select room_id, mode into target_room, round_mode from public.rounds where id = target_round;
  if target_room is null then
    raise exception 'Runde nicht gefunden.';
  end if;
  if not public.is_room_member(target_room) then
    raise exception 'Kein aktives Mitglied dieses Raums.';
  end if;
  if p_lines_count is null or p_lines_count < 1 then
    raise exception 'lines_count muss mindestens 1 sein.';
  end if;

  insert into public.wins (profile_id, round_id, room_id, lines_count)
  values (auth.uid(), target_round, target_room, p_lines_count)
  returning * into result;

  if round_mode = 'first_blood' then
    update public.rounds
    set ended_at = now()
    where id = target_round and ended_at is null;
  end if;

  return result;
end;
$$;

-- Bugfix 2, Fortsetzung: Sobald eine First-Blood-Runde endet, direkt
-- serverseitig die nächste Runde aus dem aktiven Wort-Pool ziehen (höchste
-- Stimmenzahl zuerst, Gleichstand zufällig) - unabhängig davon, ob der
-- Gewinner-Client noch online ist oder wegklickt.
create or replace function public.auto_start_next_round()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  active_count int;
  cell_count int;
  chosen_words jsonb;
begin
  if new.ended_at is null or old.ended_at is not null or new.mode <> 'first_blood' then
    return new;
  end if;

  select count(*) into active_count from public.word_pool where room_id = new.room_id and status = 'active';
  if active_count < 9 then
    return new; -- Pool zu klein, keine automatische Folgerunde möglich
  end if;

  cell_count := case
    when active_count >= 25 then 25
    when active_count >= 16 then 16
    else 9
  end;

  select jsonb_agg(word) into chosen_words
  from (
    select wp.word
    from public.word_pool wp
    left join (
      select word_id, count(*) as votes from public.word_votes group by word_id
    ) v on v.word_id = wp.id
    where wp.room_id = new.room_id and wp.status = 'active'
    order by coalesce(v.votes, 0) desc, random()
    limit cell_count
  ) s;

  insert into public.rounds (room_id, mode, words)
  values (new.room_id, new.mode, chosen_words);

  return new;
end;
$$;

create trigger rounds_auto_restart
  after update on public.rounds
  for each row
  execute function public.auto_start_next_round();
