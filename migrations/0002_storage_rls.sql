-- Storage Valet — Storage Bucket RLS Policies
-- v3.1 • Gate 2: Owner-only photo access via signed URLs

-- Create storage bucket for item photos (private by default)
INSERT INTO storage.buckets (id, name, public)
VALUES ('item-photos', 'item-photos', false)
ON CONFLICT (id) DO NOTHING;

-- Enable RLS on storage.objects
ALTER TABLE storage.objects ENABLE ROW LEVEL SECURITY;

-- Policy: Users can only SELECT their own photos
-- Path format: {user_id}/{item_id}/{uuid}.{ext}
CREATE POLICY "read-own-item-photos"
ON storage.objects FOR SELECT
TO authenticated
USING (
  bucket_id = 'item-photos'
  AND split_part(name, '/', 1) = auth.uid()::text
);

-- Policy: Users can only INSERT photos to their own folder
CREATE POLICY "upload-own-item-photos"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id = 'item-photos'
  AND split_part(name, '/', 1) = auth.uid()::text
);

-- Policy: Users can only UPDATE their own photos
CREATE POLICY "update-own-item-photos"
ON storage.objects FOR UPDATE
TO authenticated
USING (
  bucket_id = 'item-photos'
  AND split_part(name, '/', 1) = auth.uid()::text
);

-- Policy: Users can only DELETE their own photos
CREATE POLICY "delete-own-item-photos"
ON storage.objects FOR DELETE
TO authenticated
USING (
  bucket_id = 'item-photos'
  AND split_part(name, '/', 1) = auth.uid()::text
);

-- Note: All photo access in portal uses signed URLs (1h expiry)
-- created via supabase.storage.from('item-photos').createSignedUrl()
