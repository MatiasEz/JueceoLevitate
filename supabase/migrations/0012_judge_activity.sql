create table if not exists public.judge_activity (
    event_id uuid not null references public.events(id) on delete cascade,
    judge_id text not null,
    device_id text not null default '',
    state text not null default 'home',
    block_id text,
    routine_id text,
    platform text not null default '',
    updated_at timestamptz not null default now(),
    primary key (event_id, judge_id, device_id),
    constraint judge_activity_state_check
        check (state in ('home', 'viewing_sheet', 'left_sheet')),
    foreign key (event_id, judge_id)
        references public.judges(event_id, judge_id)
        on delete cascade
);

create index if not exists judge_activity_event_updated_idx
on public.judge_activity(event_id, updated_at desc);

create index if not exists judge_activity_event_judge_idx
on public.judge_activity(event_id, judge_id);

drop trigger if exists judge_activity_set_updated_at on public.judge_activity;
create trigger judge_activity_set_updated_at
before update on public.judge_activity
for each row execute function public.set_updated_at();

alter table public.judge_activity enable row level security;

drop policy if exists "anon can read judge activity" on public.judge_activity;
create policy "anon can read judge activity" on public.judge_activity
for select to anon using (true);

drop policy if exists "anon can upsert judge activity" on public.judge_activity;
create policy "anon can upsert judge activity" on public.judge_activity
for insert to anon with check (true);

drop policy if exists "anon can update judge activity" on public.judge_activity;
create policy "anon can update judge activity" on public.judge_activity
for update to anon using (true) with check (true);
