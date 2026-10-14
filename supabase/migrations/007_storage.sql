-- Storage buckets and access policies for the final schema.
-- These objects are created as part of the clean database build.

insert into storage.buckets (id, name, public)
values
  ('photos', 'photos', false),
  ('documents', 'documents', false),
  ('attachments', 'attachments', false)
on conflict (id) do nothing;

-- Student photos are private and can only be accessed by active users.
create policy "active users read student photos"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'photos'
    and app.is_active_user()
  );

create policy "authorized users upload student photos"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'photos'
    and app.is_active_user()
    and app.has_any_perm('students.manage','students.create','students.edit')
  );

create policy "authorized users delete student photos"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'photos'
    and app.is_active_user()
    and app.has_any_perm('students.manage','students.create','students.edit')
  );

-- Attachments and document files are private as well. Their application-level
-- tables enforce the entity and school relationship; these policies protect
-- the underlying objects from anonymous access.
create policy "active users read school files"
  on storage.objects for select to authenticated
  using (
    bucket_id in ('documents', 'attachments')
    and app.is_active_user()
  );

create policy "authorized users upload school files"
  on storage.objects for insert to authenticated
  with check (
    bucket_id in ('documents', 'attachments')
    and app.is_active_user()
    and (app.has_perm('documents.upload') or app.has_perm('attachments.manage') or app.has_perm('settings.manage'))
  );

create policy "authorized users delete school files"
  on storage.objects for delete to authenticated
  using (
    bucket_id in ('documents', 'attachments')
    and app.is_active_user()
    and (app.has_perm('documents.upload') or app.has_perm('attachments.manage') or app.has_perm('settings.manage'))
  );

-- School logo files are kept under a dedicated folder and are managed only by
-- users with the settings permission; student-photo access remains isolated.
drop policy if exists "settings managers upload school logos" on storage.objects;
create policy "settings managers upload school logos"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'photos'
    and name like 'logos/%'
    and app.is_active_user()
    and app.has_perm('settings.manage')
  );

drop policy if exists "settings managers delete school logos" on storage.objects;
create policy "settings managers delete school logos"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'photos'
    and name like 'logos/%'
    and app.is_active_user()
    and app.has_perm('settings.manage')
  );

notify pgrst, 'reload schema';
