-- Farmora MVP (Supabase): storage buckets and access policies.
-- Object paths always start with the uploader's user id: <bucket>/<auth.uid()>/<file>.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values
  ('avatars',        'avatars',        true,  1048576, array['image/jpeg', 'image/png', 'image/webp']),
  ('product-images', 'product-images', true,  2097152, array['image/jpeg', 'image/png', 'image/webp']),
  ('crop-images',    'crop-images',    false, 3145728, array['image/jpeg', 'image/png', 'image/webp']),
  ('demand-images',  'demand-images',  true,  2097152, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do nothing;

-- avatars: any signed-in user, own folder
create policy "avatars insert own" on storage.objects for insert to authenticated
  with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "avatars update own" on storage.objects for update to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "avatars delete own" on storage.objects for delete to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);

-- product-images: farmers, own folder
create policy "product images insert farmer" on storage.objects for insert to authenticated
  with check (bucket_id = 'product-images'
              and (storage.foldername(name))[1] = auth.uid()::text
              and public.current_app_role() = 'farmer');
create policy "product images delete own" on storage.objects for delete to authenticated
  using (bucket_id = 'product-images' and (storage.foldername(name))[1] = auth.uid()::text);

-- crop-images: private to the farmer (served via signed URLs)
create policy "crop images read own" on storage.objects for select to authenticated
  using (bucket_id = 'crop-images' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "crop images insert farmer" on storage.objects for insert to authenticated
  with check (bucket_id = 'crop-images'
              and (storage.foldername(name))[1] = auth.uid()::text
              and public.current_app_role() = 'farmer');
create policy "crop images delete own" on storage.objects for delete to authenticated
  using (bucket_id = 'crop-images' and (storage.foldername(name))[1] = auth.uid()::text);

-- demand-images: farmers (harvest photos, own folder) and admins (item images under items/)
create policy "demand images insert" on storage.objects for insert to authenticated
  with check (bucket_id = 'demand-images'
              and (((storage.foldername(name))[1] = auth.uid()::text and public.current_app_role() = 'farmer')
                   or ((storage.foldername(name))[1] = 'items' and public.is_admin())));
create policy "demand images delete" on storage.objects for delete to authenticated
  using (bucket_id = 'demand-images'
         and ((storage.foldername(name))[1] = auth.uid()::text
              or ((storage.foldername(name))[1] = 'items' and public.is_admin())));
