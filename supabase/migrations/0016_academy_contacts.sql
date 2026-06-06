create table if not exists public.academy_contacts (
    event_id uuid not null references public.events(id) on delete cascade,
    academy_key text not null,
    academy_name text not null,
    email text not null default '',
    state text not null default '',
    notes text not null default '',
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    primary key (event_id, academy_key)
);

create index if not exists academy_contacts_event_name_idx
on public.academy_contacts(event_id, academy_name);

drop trigger if exists academy_contacts_set_updated_at on public.academy_contacts;
create trigger academy_contacts_set_updated_at
before update on public.academy_contacts
for each row execute function public.set_updated_at();

alter table public.academy_contacts enable row level security;

drop policy if exists "anon can read academy contacts" on public.academy_contacts;
create policy "anon can read academy contacts" on public.academy_contacts
for select to anon using (true);

with puebla_event as (
    select id
    from public.events
    where slug = 'puebla-2026-primavera'
    limit 1
),
contacts(academy_name, email, state) as (
    values
        ('DANCE CENTRAL', 'erick23_91@hotmail.com', 'PUEBLA'),
        ('FLASHDANCE STUDIO', 'yaretzy25aa@gmail.com', 'PUEBLA'),
        ('PLATAFORMA STUDIO', 'plataformastdio@gmail.com', 'PUEBLA'),
        ('VOLARE STUDIO CIRCUS', 'nataly210988@gmail.com', 'PUEBLA'),
        ('CIMERA GYM CLUB', 'godavec90@gmail.com', 'PUEBLA'),
        ('CLUB ALPHA 2', 'brendisoj@gmail.com', 'PUEBLA'),
        ('MINERAL BALLET ACADEMIA', 'margarita116@outlook.com', 'ZACATECAS'),
        ('DIANA GALLARDO ACADEMIA DE DANZA', 'dgacademiapue@gmail.com', 'PUEBLA'),
        ('PLACA DANZA AEREA', 'placadanzaaerea@gmail.com', 'PUEBLA'),
        ('ÉLITE MUSA', 'dosamariand@gmail.com', 'PUEBLA'),
        ('GRETA DANZA AEREA', 'yalgonzalez@outlook.com', 'OAXACA'),
        ('WOLVES GYMNASTICS', 'gymnasticswolves@gmail.com', 'PUEBLA'),
        ('PARIS DANCE STUDIO', 'yalgonzalez@outlook.com', 'OAXACA')
)
insert into public.academy_contacts (event_id, academy_key, academy_name, email, state)
select
    puebla_event.id,
    public.stable_slug(contacts.academy_name),
    contacts.academy_name,
    contacts.email,
    contacts.state
from puebla_event
cross join contacts
on conflict (event_id, academy_key) do update set
    academy_name = excluded.academy_name,
    email = excluded.email,
    state = excluded.state;
