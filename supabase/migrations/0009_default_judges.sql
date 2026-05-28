alter table public.judges
add column if not exists role text not null default 'judge';

alter table public.judges
add column if not exists hero_image_name text not null default '';

with active_events as (
    select id
    from public.events
    where event_type = 'event'
      and is_active = true
),
default_judges(judge_id, name, role, sort_order, hero_image_name) as (
    values
        ('alex', 'ALEX', 'judge', 1, 'JudgeHeroAlex'),
        ('angela', 'ANGELA', 'judge', 2, 'JudgeHeroAngela'),
        ('daniel', 'DANIEL', 'judge', 3, 'JudgeHeroDaniel'),
        ('dave', 'DAVE', 'judge', 4, ''),
        ('eva', 'EVA', 'judge', 5, ''),
        ('vladimir', 'VLADIMIR', 'judge', 6, 'JudgeHeroVladimir'),
        ('yoli', 'YOLI', 'judge', 7, 'JudgeHeroYoli'),
        ('ati', 'ATI', 'admin', 8, '')
)
insert into public.judges (event_id, judge_id, name, role, sort_order, hero_image_name)
select
    active_events.id,
    default_judges.judge_id,
    default_judges.name,
    default_judges.role,
    default_judges.sort_order,
    default_judges.hero_image_name
from active_events
cross join default_judges
on conflict (event_id, judge_id) do update set
    name = excluded.name,
    role = excluded.role,
    sort_order = excluded.sort_order,
    hero_image_name = excluded.hero_image_name;
