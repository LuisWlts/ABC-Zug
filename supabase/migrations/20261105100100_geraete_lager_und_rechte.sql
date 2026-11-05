-- Rechte-Funktionen
alter function private.is_verwalter() rename to is_geraetewart;

create or replace function private.is_geraetewart()
returns boolean
language sql
security definer
set search_path = ''
stable
as $$
  select exists (
    select 1 from public.profiles
    where id = (select auth.uid()) and role in ('geraetewart', 'admin')
  );
$$;

create or replace function private.is_admin()
returns boolean
language sql
security definer
set search_path = ''
stable
as $$
  select exists (
    select 1 from public.profiles
    where id = (select auth.uid()) and role = 'admin'
  );
$$;
revoke all on function private.is_geraetewart() from public, anon;
revoke all on function private.is_admin() from public, anon;
grant execute on function private.is_geraetewart() to authenticated;
grant execute on function private.is_admin() to authenticated;

-- Rollen vergeben darf nur der Admin
alter policy "Verwalter ändern Profile" on public.profiles rename to "Admin ändert Profile";
alter policy "Admin ändert Profile" on public.profiles
  using ((select private.is_admin()))
  with check ((select private.is_admin()));

-- Prüfergebnisse: Nutzer sehen nur ihre eigenen, Gerätewart/Admin alle
alter policy "Ergebnisse lesen" on public.inspection_results
  using (
    (select private.is_geraetewart())
    or exists (select 1 from public.inspections i
               where i.id = inspection_id and i.inspector_id = (select auth.uid()))
  );

-- Geräte mit Prüffristen
create table public.devices (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  seriennummer text,
  vehicle_id uuid references public.vehicles(id) on delete set null,
  standort text,
  intervall_monate int not null default 12 check (intervall_monate > 0),
  letzte_pruefung date,
  naechste_pruefung date,
  bemerkung text,
  active boolean not null default true,
  created_at timestamptz not null default now()
);
create index on public.devices (vehicle_id);
create index on public.devices (naechste_pruefung);

create table public.device_checks (
  id uuid primary key default gen_random_uuid(),
  device_id uuid not null references public.devices(id) on delete cascade,
  geprueft_am date not null,
  geprueft_von uuid default auth.uid() references public.profiles(id) on delete set null,
  bemerkung text,
  created_at timestamptz not null default now()
);
create index on public.device_checks (device_id, geprueft_am desc);
create index on public.device_checks (geprueft_von);

-- Lagerbestand
create table public.stock (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  kategorie text,
  menge int not null default 0 check (menge >= 0),
  einheit text not null default 'Stk',
  mindestmenge int check (mindestmenge >= 0),
  lagerort text,
  bemerkung text,
  active boolean not null default true,
  updated_at timestamptz not null default now()
);

alter table public.devices enable row level security;
alter table public.device_checks enable row level security;
alter table public.stock enable row level security;

create policy "Gerätewart verwaltet Geräte" on public.devices
  for all to authenticated
  using ((select private.is_geraetewart()))
  with check ((select private.is_geraetewart()));

create policy "Gerätewart verwaltet Geräteprüfungen" on public.device_checks
  for all to authenticated
  using ((select private.is_geraetewart()))
  with check ((select private.is_geraetewart()));

create policy "Gerätewart verwaltet Lager" on public.stock
  for all to authenticated
  using ((select private.is_geraetewart()))
  with check ((select private.is_geraetewart()));
