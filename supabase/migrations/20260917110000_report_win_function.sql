-- Fehlendes Puzzlestück fürs echte Spielen: Eine Runde beenden (rounds.ended_at
-- setzen) darf laut RLS nur der Raum-Admin ("rounds: room admin write" deckt
-- alle Aktionen ab). Ein normales Mitglied, das ein Bingo erzielt, könnte die
-- Runde damit nicht wie im Konzept beschrieben ("Sobald ein Spieler ein Bingo
-- erreicht, wird die Runde beendet") selbst beenden.
--
-- Lösung: eine SECURITY DEFINER-Funktion, die den Win einträgt UND die Runde
-- beendet – kontrolliert (nur wenn der Aufrufer Mitglied des Raums ist, nur für
-- die übergebene Runde), statt die generelle Update-Policy auf rounds
-- aufzuweichen.
create or replace function public.report_win(target_round uuid, p_lines_count smallint)
returns public.wins
language plpgsql
security definer
set search_path = public
as $$
declare
  result public.wins;
  target_room uuid;
begin
  if not public.is_approved() then
    raise exception 'Account ist nicht global freigegeben.';
  end if;

  select room_id into target_room from public.rounds where id = target_round;
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

  update public.rounds
  set ended_at = now()
  where id = target_round and ended_at is null;

  return result;
end;
$$;

grant execute on function public.report_win(uuid, smallint) to authenticated;
