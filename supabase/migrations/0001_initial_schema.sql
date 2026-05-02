create extension if not exists pgcrypto;

create table if not exists public.events (
    id uuid primary key default gen_random_uuid(),
    slug text not null unique,
    name text not null,
    source_name text not null default '',
    starts_at date,
    is_active boolean not null default false,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create table if not exists public.routines (
    event_id uuid not null references public.events(id) on delete cascade,
    routine_id text not null,
    block text not null default '',
    block_title text not null default '',
    sort_order integer not null default 0,
    name text not null,
    academy text not null default '',
    division text not null default '',
    genre text not null default '',
    level text not null default '',
    category text not null default '',
    choreographer text not null default '',
    state text not null default '',
    scheduled_time text not null default '',
    duration text not null default '',
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    primary key (event_id, routine_id)
);

create table if not exists public.judges (
    event_id uuid not null references public.events(id) on delete cascade,
    judge_id text not null,
    name text not null,
    sort_order integer not null default 0,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    primary key (event_id, judge_id)
);

create table if not exists public.criteria_templates (
    event_id uuid not null references public.events(id) on delete cascade,
    template_id text not null,
    genre text not null,
    title text not null,
    max_score numeric(7,2) not null default 0,
    sort_order integer not null default 0,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    primary key (event_id, template_id)
);

create table if not exists public.criteria (
    event_id uuid not null references public.events(id) on delete cascade,
    template_id text not null,
    criterion_id integer not null,
    section text not null default '',
    label text not null,
    max_score numeric(7,2) not null,
    sort_order integer not null default 0,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    primary key (event_id, template_id, criterion_id),
    foreign key (event_id, template_id)
        references public.criteria_templates(event_id, template_id)
        on delete cascade
);

create table if not exists public.scores (
    event_id uuid not null references public.events(id) on delete cascade,
    routine_id text not null,
    judge_id text not null,
    criterion_id integer not null,
    value numeric(5,2) not null check (value >= 0 and value <= 10),
    device_id text not null default '',
    submitted_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    primary key (event_id, routine_id, judge_id, criterion_id),
    foreign key (event_id, routine_id)
        references public.routines(event_id, routine_id)
        on delete cascade,
    foreign key (event_id, judge_id)
        references public.judges(event_id, judge_id)
        on delete cascade
);

create table if not exists public.feedback (
    event_id uuid not null references public.events(id) on delete cascade,
    routine_id text not null,
    judge_id text not null,
    body text not null default '',
    device_id text not null default '',
    updated_at timestamptz not null default now(),
    primary key (event_id, routine_id, judge_id),
    foreign key (event_id, routine_id)
        references public.routines(event_id, routine_id)
        on delete cascade,
    foreign key (event_id, judge_id)
        references public.judges(event_id, judge_id)
        on delete cascade
);

create index if not exists routines_event_block_idx on public.routines(event_id, block, sort_order);
create index if not exists routines_event_category_idx on public.routines(event_id, genre, division, category);
create index if not exists scores_event_routine_idx on public.scores(event_id, routine_id);
create index if not exists scores_event_judge_idx on public.scores(event_id, judge_id);
create index if not exists feedback_event_judge_idx on public.feedback(event_id, judge_id);

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
    new.updated_at = now();
    return new;
end;
$$;

drop trigger if exists events_set_updated_at on public.events;
create trigger events_set_updated_at
before update on public.events
for each row execute function public.set_updated_at();

drop trigger if exists routines_set_updated_at on public.routines;
create trigger routines_set_updated_at
before update on public.routines
for each row execute function public.set_updated_at();

drop trigger if exists judges_set_updated_at on public.judges;
create trigger judges_set_updated_at
before update on public.judges
for each row execute function public.set_updated_at();

drop trigger if exists criteria_templates_set_updated_at on public.criteria_templates;
create trigger criteria_templates_set_updated_at
before update on public.criteria_templates
for each row execute function public.set_updated_at();

drop trigger if exists criteria_set_updated_at on public.criteria;
create trigger criteria_set_updated_at
before update on public.criteria
for each row execute function public.set_updated_at();

drop trigger if exists scores_set_updated_at on public.scores;
create trigger scores_set_updated_at
before update on public.scores
for each row execute function public.set_updated_at();

drop trigger if exists feedback_set_updated_at on public.feedback;
create trigger feedback_set_updated_at
before update on public.feedback
for each row execute function public.set_updated_at();

alter table public.events enable row level security;
alter table public.routines enable row level security;
alter table public.judges enable row level security;
alter table public.criteria_templates enable row level security;
alter table public.criteria enable row level security;
alter table public.scores enable row level security;
alter table public.feedback enable row level security;

drop policy if exists "anon can read events" on public.events;
create policy "anon can read events" on public.events
for select to anon using (true);

drop policy if exists "anon can read routines" on public.routines;
create policy "anon can read routines" on public.routines
for select to anon using (true);

drop policy if exists "anon can read judges" on public.judges;
create policy "anon can read judges" on public.judges
for select to anon using (true);

drop policy if exists "anon can read templates" on public.criteria_templates;
create policy "anon can read templates" on public.criteria_templates
for select to anon using (true);

drop policy if exists "anon can read criteria" on public.criteria;
create policy "anon can read criteria" on public.criteria
for select to anon using (true);

drop policy if exists "anon can read scores" on public.scores;
create policy "anon can read scores" on public.scores
for select to anon using (true);

drop policy if exists "anon can upsert scores" on public.scores;
create policy "anon can upsert scores" on public.scores
for insert to anon with check (true);

drop policy if exists "anon can update scores" on public.scores;
create policy "anon can update scores" on public.scores
for update to anon using (true) with check (true);

drop policy if exists "anon can read feedback" on public.feedback;
create policy "anon can read feedback" on public.feedback
for select to anon using (true);

drop policy if exists "anon can upsert feedback" on public.feedback;
create policy "anon can upsert feedback" on public.feedback
for insert to anon with check (true);

drop policy if exists "anon can update feedback" on public.feedback;
create policy "anon can update feedback" on public.feedback
for update to anon using (true) with check (true);
