alter table public.judges
add column if not exists photo_data text not null default '';

alter table public.judges
add column if not exists assigned_block_ids text[] not null default '{}';
