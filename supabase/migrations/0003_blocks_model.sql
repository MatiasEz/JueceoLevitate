create extension if not exists pgcrypto;

create or replace function public.stable_slug(value text)
returns text
language sql
immutable
as $$
    select coalesce(
        nullif(
            trim(both '-' from regexp_replace(
                lower(translate(coalesce(value, ''), 'ÁÉÍÓÚÜÑáéíóúüñ', 'AEIOUUNaeiouun')),
                '[^a-z0-9]+',
                '-',
                'g'
            )),
            ''
        ),
        'sin-dato'
    );
$$;

alter table public.events
add column if not exists event_type text not null default 'event';

alter table public.events
drop constraint if exists events_event_type_check;

alter table public.events
add constraint events_event_type_check
check (event_type in ('event', 'legacy_block', 'archived'));

create table if not exists public.blocks (
    id uuid primary key default gen_random_uuid(),
    event_id uuid not null references public.events(id) on delete cascade,
    block_id text not null,
    legacy_event_id uuid references public.events(id) on delete set null,
    name text not null,
    title text not null default '',
    sort_order integer not null default 0,
    is_active boolean not null default false,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    unique (event_id, block_id)
);

alter table public.routines
add column if not exists block_id text;

insert into public.blocks (event_id, block_id, legacy_event_id, name, title, sort_order, is_active)
select
    routines.event_id,
    public.stable_slug(coalesce(nullif(routines.block, ''), events.slug)),
    null::uuid,
    coalesce(nullif(routines.block, ''), events.name),
    coalesce(max(nullif(routines.block_title, '')), ''),
    min(routines.sort_order),
    events.is_active
from public.routines
join public.events on events.id = routines.event_id
group by
    routines.event_id,
    public.stable_slug(coalesce(nullif(routines.block, ''), events.slug)),
    coalesce(nullif(routines.block, ''), events.name),
    events.is_active
on conflict (event_id, block_id) do update set
    name = excluded.name,
    title = excluded.title,
    sort_order = excluded.sort_order,
    is_active = excluded.is_active;

update public.routines
set block_id = public.stable_slug(coalesce(nullif(block, ''), events.slug))
from public.events
where events.id = routines.event_id
  and (routines.block_id is null or routines.block_id = '');

alter table public.routines
alter column block_id set default '';

alter table public.routines
alter column block_id set not null;

alter table public.scores
add column if not exists block_id text not null default '';

update public.scores
set block_id = routines.block_id
from public.routines
where routines.event_id = scores.event_id
  and routines.routine_id = scores.routine_id
  and scores.block_id = '';

alter table public.feedback
add column if not exists block_id text not null default '';

update public.feedback
set block_id = routines.block_id
from public.routines
where routines.event_id = feedback.event_id
  and routines.routine_id = feedback.routine_id
  and feedback.block_id = '';

alter table public.routines
drop constraint if exists routines_event_block_fk;

alter table public.routines
add constraint routines_event_block_fk
foreign key (event_id, block_id)
references public.blocks(event_id, block_id)
on delete cascade;

create index if not exists blocks_event_sort_idx on public.blocks(event_id, sort_order);
create index if not exists blocks_event_active_idx on public.blocks(event_id, is_active);
create index if not exists routines_event_block_id_idx on public.routines(event_id, block_id, sort_order);
create index if not exists scores_event_block_idx on public.scores(event_id, block_id);
create index if not exists feedback_event_block_idx on public.feedback(event_id, block_id);

drop trigger if exists blocks_set_updated_at on public.blocks;
create trigger blocks_set_updated_at
before update on public.blocks
for each row execute function public.set_updated_at();

alter table public.blocks enable row level security;

drop policy if exists "anon can read blocks" on public.blocks;
create policy "anon can read blocks" on public.blocks
for select to anon using (true);
