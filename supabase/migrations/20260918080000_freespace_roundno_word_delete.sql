-- Backlog von gestern: Freifeld (togglebar), Rundennummer, Wörter löschen.

-- ============================================================
-- Freifeld: pro Raum ein-/ausschaltbar (kein globaler Zwang)
-- ============================================================
alter table public.rooms add column free_space boolean not null default false;

-- ============================================================
-- Rundennummer: fortlaufend pro Raum, automatisch vergeben - egal ob die
-- Runde manuell (Client) oder automatisch (Trigger unten) angelegt wird.
-- ============================================================
alter table public.rounds add column round_no integer;

create or replace function public.set_round_no()
returns trigger
language plpgsql
as $$
begin
  if new.round_no is null then
    select coalesce(max(round_no), 0) + 1 into new.round_no
    from public.rounds where room_id = new.room_id;
  end if;
  return new;
end;
$$;

create trigger rounds_set_round_no
  before insert on public.rounds
  for each row
  execute function public.set_round_no();

-- ============================================================
-- Wörter aus dem Pool löschen dürfen (bisher nur select/insert/update)
-- ============================================================
create policy "word_pool: room admin delete"
  on public.word_pool for delete
  to authenticated
  using (public.is_room_admin(room_id));

-- ============================================================
-- auto_start_next_round: jetzt Freifeld-bewusst (ein Wort weniger ziehen,
-- wenn die Rastergröße ungerade ist - 3x3/5x5 haben eine echte Mitte, 4x4
-- nicht, dort bleibt das Freifeld ohne Wirkung).
-- ============================================================
create or replace function public.auto_start_next_round()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  active_count int;
  grid_size int;
  cell_count int;
  room_free_space boolean;
  chosen_words jsonb;
begin
  if new.ended_at is null or old.ended_at is not null or new.mode <> 'first_blood' then
    return new;
  end if;

  select count(*) into active_count from public.word_pool where room_id = new.room_id and status = 'active';
  if active_count < 9 then
    return new;
  end if;

  select free_space into room_free_space from public.rooms where id = new.room_id;

  grid_size := case
    when active_count >= 25 then 5
    when active_count >= 16 then 4
    else 3
  end;

  cell_count := case
    when room_free_space and grid_size in (3, 5) then grid_size * grid_size - 1
    else grid_size * grid_size
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
