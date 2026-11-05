-- Einheitsführung hat dieselben Datenrechte wie der Gerätewart
create or replace function private.is_geraetewart()
returns boolean
language sql
security definer
set search_path = ''
stable
as $$
  select exists (
    select 1 from public.profiles
    where id = (select auth.uid())
      and role in ('geraetewart', 'einheitsfuehrung', 'admin')
  );
$$;
