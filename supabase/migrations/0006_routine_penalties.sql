create table if not exists public.penalties (
    event_id uuid not null references public.events(id) on delete cascade,
    block_id text not null default '',
    routine_id text not null,
    judge_id text not null,
    value numeric(5,2) not null default 0,
    device_id text not null default '',
    updated_at timestamptz not null default now(),
    primary key (event_id, routine_id, judge_id),
    constraint penalties_value_check
        check (value >= -100 and value <= 0),
    foreign key (event_id, routine_id)
        references public.routines(event_id, routine_id)
        on delete cascade,
    foreign key (event_id, judge_id)
        references public.judges(event_id, judge_id)
        on delete cascade
);

create index if not exists penalties_event_block_idx
on public.penalties(event_id, block_id);

create index if not exists penalties_event_judge_idx
on public.penalties(event_id, judge_id);

drop trigger if exists penalties_set_updated_at on public.penalties;
create trigger penalties_set_updated_at
before update on public.penalties
for each row execute function public.set_updated_at();

alter table public.penalties enable row level security;

drop policy if exists "anon can read penalties" on public.penalties;
create policy "anon can read penalties" on public.penalties
for select to anon using (true);

drop policy if exists "anon can upsert penalties" on public.penalties;
create policy "anon can upsert penalties" on public.penalties
for insert to anon with check (true);

drop policy if exists "anon can update penalties" on public.penalties;
create policy "anon can update penalties" on public.penalties
for update to anon using (true) with check (true);
