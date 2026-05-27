alter table public.judges
add column if not exists hero_image_name text not null default '';
