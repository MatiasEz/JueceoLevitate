create table if not exists public.excel_imports (
    id uuid primary key default gen_random_uuid(),
    event_slug text not null,
    event_name text not null,
    filename text not null,
    file_size integer not null check (file_size > 0),
    payload_base64 text not null,
    status text not null default 'pending',
    error_message text,
    device_id text not null default '',
    created_at timestamptz not null default now(),
    processed_at timestamptz
);

create index if not exists excel_imports_status_created_idx
on public.excel_imports(status, created_at);

alter table public.excel_imports enable row level security;

drop policy if exists "anon can create excel imports" on public.excel_imports;
create policy "anon can create excel imports" on public.excel_imports
for insert to anon
with check (status = 'pending');
