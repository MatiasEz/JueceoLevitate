alter table public.special_awards
add column if not exists manual_value text;

alter table public.special_awards
alter column routine_id drop not null;

delete from public.special_awards
where award = 'best_porra'
  and nullif(btrim(coalesce(manual_value, '')), '') is null;

update public.special_awards
set manual_value = null
where award <> 'best_porra';

alter table public.special_awards
drop constraint if exists special_awards_assignment_check;

alter table public.special_awards
add constraint special_awards_assignment_check
check (
    (
        award = 'best_porra'
        and routine_id is null
        and nullif(btrim(coalesce(manual_value, '')), '') is not null
    )
    or
    (
        award <> 'best_porra'
        and routine_id is not null
        and nullif(btrim(coalesce(manual_value, '')), '') is null
    )
);
