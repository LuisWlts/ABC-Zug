-- Einheiten
create table public.units (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  sort int not null default 0
);
insert into public.units (name, sort) values ('Heinsberg', 1), ('Hückelhoven', 2);
alter table public.units enable row level security;

-- Zuordnung
alter table public.profiles add column unit_id uuid references public.units(id) on delete set null;
create index on public.profiles (unit_id);

alter table public.vehicles add column unit_id uuid references public.units(id);
alter table public.devices add column unit_id uuid references public.units(id);
alter table public.stock add column unit_id uuid references public.units(id);

-- vorhandene Daten vorläufig Heinsberg zuordnen
update public.vehicles set unit_id = (select id from public.units where name = 'Heinsberg') where unit_id is null;
update public.devices set unit_id = (select id from public.units where name = 'Heinsberg') where unit_id is null;
update public.stock set unit_id = (select id from public.units where name = 'Heinsberg') where unit_id is null;

alter table public.vehicles alter column unit_id set not null;
alter table public.devices alter column unit_id set not null;
alter table public.stock alter column unit_id set not null;
create index on public.vehicles (unit_id);
create index on public.devices (unit_id);
create index on public.stock (unit_id);

-- Hilfsfunktionen für die Rechte
create or replace function private.my_unit()
returns uuid
language sql
security definer
set search_path = ''
stable
as $$
  select unit_id from public.profiles where id = (select auth.uid());
$$;

create or replace function private.sees_all_units()
returns boolean
language sql
security definer
set search_path = ''
stable
as $$
  select exists (
    select 1 from public.profiles
    where id = (select auth.uid()) and role in ('einheitsfuehrung', 'admin')
  );
$$;

create or replace function private.can_access_unit(u uuid)
returns boolean
language sql
security definer
set search_path = ''
stable
as $$
  select private.sees_all_units() or (u is not null and u = private.my_unit());
$$;

create or replace function private.vehicle_ok(v uuid)
returns boolean
language sql
security definer
set search_path = ''
stable
as $$
  select private.can_access_unit((select unit_id from public.vehicles where id = v));
$$;

create or replace function private.inspection_ok(i uuid)
returns boolean
language sql
security definer
set search_path = ''
stable
as $$
  select private.vehicle_ok((select vehicle_id from public.inspections where id = i));
$$;

create or replace function private.inspection_own(i uuid)
returns boolean
language sql
security definer
set search_path = ''
stable
as $$
  select exists (
    select 1 from public.inspections
    where id = i and inspector_id = (select auth.uid())
  );
$$;

create or replace function private.device_ok(d uuid)
returns boolean
language sql
security definer
set search_path = ''
stable
as $$
  select private.can_access_unit((select unit_id from public.devices where id = d));
$$;

revoke all on function private.my_unit() from public, anon;
revoke all on function private.sees_all_units() from public, anon;
revoke all on function private.can_access_unit(uuid) from public, anon;
revoke all on function private.vehicle_ok(uuid) from public, anon;
revoke all on function private.inspection_ok(uuid) from public, anon;
revoke all on function private.inspection_own(uuid) from public, anon;
revoke all on function private.device_ok(uuid) from public, anon;
grant execute on function private.my_unit() to authenticated;
grant execute on function private.sees_all_units() to authenticated;
grant execute on function private.can_access_unit(uuid) to authenticated;
grant execute on function private.vehicle_ok(uuid) to authenticated;
grant execute on function private.inspection_ok(uuid) to authenticated;
grant execute on function private.inspection_own(uuid) to authenticated;
grant execute on function private.device_ok(uuid) to authenticated;

-- Standard-Einheit beim Anlegen = eigene Einheit
alter table public.vehicles alter column unit_id set default private.my_unit();
alter table public.devices alter column unit_id set default private.my_unit();
alter table public.stock alter column unit_id set default private.my_unit();

-- Einheiten lesen alle, ändern nur Admin
create policy "Einheiten lesen" on public.units
  for select to authenticated using (true);
create policy "Admin verwaltet Einheiten" on public.units
  for all to authenticated
  using ((select private.is_admin())) with check ((select private.is_admin()));

-- Fahrzeuge
alter policy "Fahrzeuge lesen" on public.vehicles
  using (private.can_access_unit(unit_id));
alter policy "Verwalter legen Fahrzeuge an" on public.vehicles
  with check ((select private.is_geraetewart()) and private.can_access_unit(unit_id));
alter policy "Verwalter ändern Fahrzeuge" on public.vehicles
  using ((select private.is_geraetewart()) and private.can_access_unit(unit_id))
  with check ((select private.is_geraetewart()) and private.can_access_unit(unit_id));
alter policy "Verwalter löschen Fahrzeuge" on public.vehicles
  using ((select private.is_geraetewart()) and private.can_access_unit(unit_id));

-- Checklisten-Positionen
alter policy "Positionen lesen" on public.checklist_items
  using (private.vehicle_ok(vehicle_id));
alter policy "Verwalter legen Positionen an" on public.checklist_items
  with check ((select private.is_geraetewart()) and private.vehicle_ok(vehicle_id));
alter policy "Verwalter ändern Positionen" on public.checklist_items
  using ((select private.is_geraetewart()) and private.vehicle_ok(vehicle_id))
  with check ((select private.is_geraetewart()) and private.vehicle_ok(vehicle_id));
alter policy "Verwalter löschen Positionen" on public.checklist_items
  using ((select private.is_geraetewart()) and private.vehicle_ok(vehicle_id));

-- Prüfungen
alter policy "Prüfungen lesen" on public.inspections
  using (private.vehicle_ok(vehicle_id));
alter policy "Prüfung selbst anlegen" on public.inspections
  with check (inspector_id = (select auth.uid()) and private.vehicle_ok(vehicle_id));
alter policy "Eigene Prüfung oder Verwalter ändern" on public.inspections
  using ((inspector_id = (select auth.uid()) or (select private.is_geraetewart())) and private.vehicle_ok(vehicle_id))
  with check ((inspector_id = (select auth.uid()) or (select private.is_geraetewart())) and private.vehicle_ok(vehicle_id));
alter policy "Verwalter löschen Prüfungen" on public.inspections
  using ((select private.is_geraetewart()) and private.vehicle_ok(vehicle_id));

-- Prüfergebnisse
alter policy "Ergebnisse lesen" on public.inspection_results
  using (private.inspection_ok(inspection_id)
         and ((select private.is_geraetewart()) or private.inspection_own(inspection_id)));
alter policy "Ergebnisse zur eigenen Prüfung anlegen" on public.inspection_results
  with check (private.inspection_ok(inspection_id)
              and ((select private.is_geraetewart()) or private.inspection_own(inspection_id)));
alter policy "Eigene Ergebnisse oder Verwalter ändern" on public.inspection_results
  using (private.inspection_ok(inspection_id)
         and ((select private.is_geraetewart()) or private.inspection_own(inspection_id)))
  with check (private.inspection_ok(inspection_id)
              and ((select private.is_geraetewart()) or private.inspection_own(inspection_id)));
alter policy "Verwalter löschen Ergebnisse" on public.inspection_results
  using ((select private.is_geraetewart()) and private.inspection_ok(inspection_id));

-- Geräte, Geräteprüfungen, Lager
alter policy "Gerätewart verwaltet Geräte" on public.devices
  using ((select private.is_geraetewart()) and private.can_access_unit(unit_id))
  with check ((select private.is_geraetewart()) and private.can_access_unit(unit_id));
alter policy "Gerätewart verwaltet Geräteprüfungen" on public.device_checks
  using ((select private.is_geraetewart()) and private.device_ok(device_id))
  with check ((select private.is_geraetewart()) and private.device_ok(device_id));
alter policy "Gerätewart verwaltet Lager" on public.stock
  using ((select private.is_geraetewart()) and private.can_access_unit(unit_id))
  with check ((select private.is_geraetewart()) and private.can_access_unit(unit_id));

-- Fehlbestand mit Einheit
create or replace view public.fehlbestand
with (security_invoker = true) as
select
  r.id as result_id,
  v.id as vehicle_id,
  v.name as fahrzeug,
  v.kennzeichen,
  ci.bereich,
  ci.name as position,
  ci.soll_menge,
  r.status,
  r.ist_menge,
  r.note,
  r.bestellt,
  i.completed_at as geprueft_am,
  p.name as geprueft_von,
  pi.name as parent_name,
  v.unit_id as unit_id
from public.inspections i
join public.vehicles v on v.id = i.vehicle_id
join public.inspection_results r on r.inspection_id = i.id
join public.checklist_items ci on ci.id = r.item_id
left join public.checklist_items pi on pi.id = ci.parent_id
left join public.profiles p on p.id = i.inspector_id
where i.completed_at is not null
  and i.completed_at = (
    select max(i2.completed_at) from public.inspections i2
    where i2.vehicle_id = i.vehicle_id and i2.completed_at is not null
  )
  and r.status <> 'ok'
  and not exists (
    select 1 from public.inspection_results pr
    where pr.inspection_id = i.id and pr.item_id = ci.parent_id and pr.status = 'fehlt'
  );
