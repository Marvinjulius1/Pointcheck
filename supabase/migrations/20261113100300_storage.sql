-- Storage buckets for profile photos and post images.
--
-- Files are stored as <user id>/<file name>. Everyone may read (the URLs are only shown
-- to people who may see the profile or post anyway); only the owner writes to their folder.
--
-- Runs only on Supabase (needs the `storage` schema). For local tests this file is skipped.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
    ('avatars', 'avatars', true, 2 * 1024 * 1024, array['image/jpeg', 'image/png', 'image/webp']),
    ('posts', 'posts', true, 5 * 1024 * 1024, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do update
    set public = excluded.public,
        file_size_limit = excluded.file_size_limit,
        allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "images: public read" on storage.objects;
create policy "images: public read" on storage.objects
    for select using (bucket_id in ('avatars', 'posts'));

drop policy if exists "images: owner writes" on storage.objects;
create policy "images: owner writes" on storage.objects
    for insert to authenticated
    with check (bucket_id in ('avatars', 'posts') and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "images: owner updates" on storage.objects;
create policy "images: owner updates" on storage.objects
    for update to authenticated
    using (bucket_id in ('avatars', 'posts') and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "images: owner deletes" on storage.objects;
create policy "images: owner deletes" on storage.objects
    for delete to authenticated
    using (bucket_id in ('avatars', 'posts') and (storage.foldername(name))[1] = auth.uid()::text);
