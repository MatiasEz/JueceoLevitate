alter table public.routines
add column if not exists participant text not null default '';
