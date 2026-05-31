alter table public.special_awards
add column if not exists manual_value text;

alter table public.special_awards
alter column routine_id drop not null;

alter table public.special_awards
drop constraint if exists special_awards_assignment_check;

update public.special_awards as sa
set manual_value = coalesce(
    nullif(btrim(sa.manual_value), ''),
    concat('#', routines.routine_id, ' ', routines.name)
)
from public.routines
where sa.event_id = routines.event_id
  and sa.routine_id = routines.routine_id
  and nullif(btrim(coalesce(sa.manual_value, '')), '') is null;

update public.special_awards
set manual_value = nullif(btrim(coalesce(manual_value, '')), '');

delete from public.special_awards
where manual_value is null;

update public.special_awards
set routine_id = null;

alter table public.special_awards
add constraint special_awards_assignment_check
check (
    routine_id is null
    and nullif(btrim(coalesce(manual_value, '')), '') is not null
);
