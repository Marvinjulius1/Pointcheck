-- Storage bucket for hall logos and campaign images.
--
-- Everyone may read; only the Pointcheck team uploads (Supabase dashboard → Storage,
-- which uses the service role). There is deliberately no write policy for app users.
--
-- Runs only on Supabase (needs the `storage` schema). For local tests this file is skipped.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('halls', 'halls', true, 5 * 1024 * 1024, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do update
    set public = excluded.public,
        file_size_limit = excluded.file_size_limit,
        allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "halls: public read" on storage.objects;
create policy "halls: public read" on storage.objects
    for select using (bucket_id = 'halls');
