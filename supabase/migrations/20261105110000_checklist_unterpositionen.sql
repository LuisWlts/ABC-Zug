-- Unterpositionen (Inhalte, z. B. Verbandskasten -> Pflaster)
alter table public.checklist_items
  add column parent_id uuid references public.checklist_items(id) on delete cascade;
create index on public.checklist_items (parent_id);

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
  pi.name as parent_name
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
