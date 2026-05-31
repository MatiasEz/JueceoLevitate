create table if not exists public.special_awards (
    event_id uuid not null references public.events(id) on delete cascade,
    block_id text not null default '',
    award text not null,
    routine_id text not null,
    device_id text not null default '',
    updated_at timestamptz not null default now(),
    primary key (event_id, block_id, award),
    constraint special_awards_award_check
        check (award in ('best_costume', 'best_music', 'best_choreographic_idea', 'best_porra')),
    foreign key (event_id, block_id)
        references public.blocks(event_id, block_id)
        on delete cascade,
    foreign key (event_id, routine_id)
        references public.routines(event_id, routine_id)
        on delete cascade
);

create index if not exists special_awards_event_block_idx
on public.special_awards(event_id, block_id);

create index if not exists special_awards_event_routine_idx
on public.special_awards(event_id, routine_id);

drop trigger if exists special_awards_set_updated_at on public.special_awards;
create trigger special_awards_set_updated_at
before update on public.special_awards
for each row execute function public.set_updated_at();

alter table public.special_awards enable row level security;

drop policy if exists "anon can read special awards" on public.special_awards;
create policy "anon can read special awards" on public.special_awards
for select to anon using (true);

drop policy if exists "anon can upsert special awards" on public.special_awards;
create policy "anon can upsert special awards" on public.special_awards
for insert to anon with check (true);

drop policy if exists "anon can update special awards" on public.special_awards;
create policy "anon can update special awards" on public.special_awards
for update to anon using (true) with check (true);

drop policy if exists "anon can delete special awards" on public.special_awards;
create policy "anon can delete special awards" on public.special_awards
for delete to anon using (true);
