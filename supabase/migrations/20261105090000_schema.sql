-- Grundschema: Rollen, Fahrzeuge, Checklisten, Prüfungen
create schema if not exists private;

-- Rollen (werden in späteren Migrationen umbenannt und erweitert)
create type public.user_role as enum ('helfer', 'verwalter');

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  name text,
  role public.user_role not null default 'helfer',
  created_at timestamptz not null default now()
);

create or replace function private.is_verwalter()
returns boolean
language sql
security definer
set search_path = ''
stable
as $$
  select exists (
    select 1 from public.profiles
    where id = (select auth.uid()) and role = 'verwalter'
  );
$$;
revoke all on function private.is_verwalter() from public, anon;
grant usage on schema private to authenticated;
grant execute on function private.is_verwalter() to authenticated;

create or replace function private.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, name)
  values (new.id, coalesce(new.raw_user_meta_data->>'name', split_part(new.email, '@', 1)));
  return new;
end;
$$;
revoke all on function private.handle_new_user() from public, anon, authenticated;

create trigger on_auth_user_created
after insert on auth.users
for each row execute function private.handle_new_user();

-- Fahrzeuge
create table public.vehicles (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  kennzeichen text,
  sort int not null default 0,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

-- Positionen der Checkliste je Fahrzeug
create table public.checklist_items (
  id uuid primary key default gen_random_uuid(),
  vehicle_id uuid not null references public.vehicles(id) on delete cascade,
  bereich text not null default 'Allgemein',
  name text not null,
  soll_menge int not null default 1 check (soll_menge >= 0),
  sort int not null default 0,
  active boolean not null default true,
  created_at timestamptz not null default now()
);
create index on public.checklist_items (vehicle_id);

-- Prüfungen
create table public.inspections (
  id uuid primary key default gen_random_uuid(),
  vehicle_id uuid not null references public.vehicles(id) on delete cascade,
  inspector_id uuid not null default auth.uid() references public.profiles(id),
  started_at timestamptz not null default now(),
  completed_at timestamptz,
  note text
);
create index on public.inspections (vehicle_id, completed_at desc);
create index on public.inspections (inspector_id);

create type public.item_status as enum ('ok', 'fehlt', 'defekt');

create table public.inspection_results (
  id uuid primary key default gen_random_uuid(),
  inspection_id uuid not null references public.inspections(id) on delete cascade,
  item_id uuid not null references public.checklist_items(id) on delete cascade,
  status public.item_status not null default 'ok',
  ist_menge int,
  note text,
  bestellt boolean not null default false,
  unique (inspection_id, item_id)
);
create index on public.inspection_results (item_id);

-- Row Level Security
alter table public.profiles enable row level security;
alter table public.vehicles enable row level security;
alter table public.checklist_items enable row level security;
alter table public.inspections enable row level security;
alter table public.inspection_results enable row level security;

-- profiles
create policy "eigenes Profil oder Verwalter lesen" on public.profiles
  for select to authenticated
  using (id = (select auth.uid()) or (select private.is_verwalter()));
create policy "Verwalter ändern Profile" on public.profiles
  for update to authenticated
  using ((select private.is_verwalter()))
  with check ((select private.is_verwalter()));

-- vehicles
create policy "Fahrzeuge lesen" on public.vehicles
  for select to authenticated using (true);
create policy "Verwalter legen Fahrzeuge an" on public.vehicles
  for insert to authenticated with check ((select private.is_verwalter()));
create policy "Verwalter ändern Fahrzeuge" on public.vehicles
  for update to authenticated
  using ((select private.is_verwalter())) with check ((select private.is_verwalter()));
create policy "Verwalter löschen Fahrzeuge" on public.vehicles
  for delete to authenticated using ((select private.is_verwalter()));

-- checklist_items
create policy "Positionen lesen" on public.checklist_items
  for select to authenticated using (true);
create policy "Verwalter legen Positionen an" on public.checklist_items
  for insert to authenticated with check ((select private.is_verwalter()));
create policy "Verwalter ändern Positionen" on public.checklist_items
  for update to authenticated
  using ((select private.is_verwalter())) with check ((select private.is_verwalter()));
create policy "Verwalter löschen Positionen" on public.checklist_items
  for delete to authenticated using ((select private.is_verwalter()));

-- inspections
create policy "Prüfungen lesen" on public.inspections
  for select to authenticated using (true);
create policy "Prüfung selbst anlegen" on public.inspections
  for insert to authenticated with check (inspector_id = (select auth.uid()));
create policy "Eigene Prüfung oder Verwalter ändern" on public.inspections
  for update to authenticated
  using (inspector_id = (select auth.uid()) or (select private.is_verwalter()))
  with check (inspector_id = (select auth.uid()) or (select private.is_verwalter()));
create policy "Verwalter löschen Prüfungen" on public.inspections
  for delete to authenticated using ((select private.is_verwalter()));

-- inspection_results
create policy "Ergebnisse lesen" on public.inspection_results
  for select to authenticated using (true);
create policy "Ergebnisse zur eigenen Prüfung anlegen" on public.inspection_results
  for insert to authenticated
  with check (
    exists (select 1 from public.inspections i
            where i.id = inspection_id and i.inspector_id = (select auth.uid()))
    or (select private.is_verwalter())
  );
create policy "Eigene Ergebnisse oder Verwalter ändern" on public.inspection_results
  for update to authenticated
  using (
    exists (select 1 from public.inspections i
            where i.id = inspection_id and i.inspector_id = (select auth.uid()))
    or (select private.is_verwalter())
  )
  with check (
    exists (select 1 from public.inspections i
            where i.id = inspection_id and i.inspector_id = (select auth.uid()))
    or (select private.is_verwalter())
  );
create policy "Verwalter löschen Ergebnisse" on public.inspection_results
  for delete to authenticated using ((select private.is_verwalter()));

-- Fehlbestand: Ergebnis der jeweils letzten abgeschlossenen Prüfung je Fahrzeug
create view public.fehlbestand
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
  p.name as geprueft_von
from public.inspections i
join public.vehicles v on v.id = i.vehicle_id
join public.inspection_results r on r.inspection_id = i.id
join public.checklist_items ci on ci.id = r.item_id
left join public.profiles p on p.id = i.inspector_id
where i.completed_at is not null
  and i.completed_at = (
    select max(i2.completed_at) from public.inspections i2
    where i2.vehicle_id = i.vehicle_id and i2.completed_at is not null
  )
  and r.status <> 'ok';

grant select on public.fehlbestand to authenticated;
