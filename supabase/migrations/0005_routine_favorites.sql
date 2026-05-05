create table if not exists public.routine_favorites (
    event_id uuid not null references public.events(id) on delete cascade,
    block_id text not null default '',
    routine_id text not null,
    judge_id text not null,
    category text not null,
    device_id text not null default '',
    updated_at timestamptz not null default now(),
    primary key (event_id, block_id, judge_id, category),
    constraint routine_favorites_category_check
        check (category in ('costume', 'choreography', 'music')),
    foreign key (event_id, block_id)
        references public.blocks(event_id, block_id)
        on delete cascade,
    foreign key (event_id, routine_id)
        references public.routines(event_id, routine_id)
        on delete cascade,
    foreign key (event_id, judge_id)
        references public.judges(event_id, judge_id)
        on delete cascade
);

create index if not exists routine_favorites_event_block_idx
on public.routine_favorites(event_id, block_id);

create index if not exists routine_favorites_event_routine_idx
on public.routine_favorites(event_id, routine_id);

drop trigger if exists routine_favorites_set_updated_at on public.routine_favorites;
create trigger routine_favorites_set_updated_at
before update on public.routine_favorites
for each row execute function public.set_updated_at();

alter table public.routine_favorites enable row level security;

drop policy if exists "anon can read routine favorites" on public.routine_favorites;
create policy "anon can read routine favorites" on public.routine_favorites
for select to anon using (true);

drop policy if exists "anon can upsert routine favorites" on public.routine_favorites;
create policy "anon can upsert routine favorites" on public.routine_favorites
for insert to anon with check (true);

drop policy if exists "anon can update routine favorites" on public.routine_favorites;
create policy "anon can update routine favorites" on public.routine_favorites
for update to anon using (true) with check (true);

drop policy if exists "anon can delete routine favorites" on public.routine_favorites;
create policy "anon can delete routine favorites" on public.routine_favorites
for delete to anon using (true);
