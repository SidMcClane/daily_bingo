-- Ergänzungen für den vollen Lobby/Profil/Admin-Ausbau des Frontends:

-- 1) Farbe fürs Profil (Avatar-Hintergrund), siehe konzept.md "Profil"-Feature.
alter table public.profiles add column color text;

-- 2) Bugfix: Der Selbst-Escalation-Schutz hat auch legitime Aktionen eines
-- Plattform-Admins auf FREMDEN Profilen blockiert (er kannte keinen
-- Unterschied zwischen "ich ändere mich selbst" und "ich ändere jemand
-- anderen"). Jetzt greift die Sperre nur noch, wenn ein Nutzer sein EIGENES
-- Profil ändert.
create or replace function public.prevent_profile_privilege_escalation()
returns trigger
language plpgsql
as $$
begin
  if auth.uid() is null or auth.uid() <> new.id then
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

-- 3) Fehlende Policy: Bisher durfte laut RLS niemand ein FREMDES Profil
-- updaten (nur "update own" existierte) - Freigeben/Sperren durch den
-- Plattform-Admin wäre also nie durchgekommen.
create policy "profiles: platform admin updates others"
  on public.profiles for update
  to authenticated
  using (public.is_platform_admin())
  with check (public.is_platform_admin());

-- 4) Fehlende Policy: Raum-Admins sollen Name/Sichtbarkeit/Beitrittscode
-- ihres EIGENEN Raums pflegen dürfen, nicht nur der Plattform-Admin.
create policy "rooms: room admin updates own room"
  on public.rooms for update
  to authenticated
  using (public.is_room_admin(id))
  with check (public.is_room_admin(id));
