alter table public.judges
add column if not exists role text not null default 'judge';

alter table public.judges
drop constraint if exists judges_role_check;

alter table public.judges
add constraint judges_role_check
check (role in ('judge', 'admin'));

update public.judges
set role = 'admin', name = 'ATI'
where judge_id = 'ati'
   or public.stable_slug(name) = 'ati';

with target_events as (
    select id
    from public.events
    where event_type = 'event'
      and (is_active = true or slug = 'levitate-segunda-edicion-2024')
),
next_sort as (
    select
        target_events.id as event_id,
        coalesce(max(judges.sort_order), 0) + 1 as sort_order
    from target_events
    left join public.judges on judges.event_id = target_events.id
    group by target_events.id
)
insert into public.judges (event_id, judge_id, name, role, sort_order)
select event_id, 'ati', 'ATI', 'admin', sort_order
from next_sort
on conflict (event_id, judge_id) do update set
    name = excluded.name,
    role = excluded.role;
