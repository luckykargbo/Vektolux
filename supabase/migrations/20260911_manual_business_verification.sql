-- ==============================================================================
-- Migration: Manual Business Verification Pipeline & Admin Workflow
-- Database: PostgreSQL (Supabase)
-- ==============================================================================

-- 1. Create verification_status ENUM
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'verification_status') THEN
        CREATE TYPE verification_status AS ENUM ('pending', 'approved', 'rejected', 'suspended');
    END IF;
END $$;

-- 2. Ensure agent profile table exists or add verification fields
ALTER TABLE IF EXISTS public.profiles
    ADD COLUMN IF NOT EXISTS business_name TEXT,
    ADD COLUMN IF NOT EXISTS tin_number TEXT,
    ADD COLUMN IF NOT EXISTS document_url TEXT,
    ADD COLUMN IF NOT EXISTS verification_status verification_status NOT NULL DEFAULT 'pending',
    ADD COLUMN IF NOT EXISTS rejection_reason TEXT,
    ADD COLUMN IF NOT EXISTS verified_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS verified_by UUID REFERENCES auth.users(id) ON DELETE SET NULL;

-- Create index on verification_status for admin queue performance
CREATE INDEX IF NOT EXISTS idx_profiles_verification_status 
    ON public.profiles(verification_status);

CREATE INDEX IF NOT EXISTS idx_profiles_role_verification 
    ON public.profiles(role, verification_status);

-- 3. Security & Column-Level Mutation Guard
-- Prevent non-admins from altering verification_status, rejection_reason, verified_at, verified_by
CREATE OR REPLACE FUNCTION public.check_agent_verification_mutation()
RETURNS TRIGGER AS $$
DECLARE
    current_role TEXT;
BEGIN
    -- Check caller role from profiles or JWT claim
    SELECT role INTO current_role FROM public.profiles WHERE id = auth.uid();

    -- Allow service role or admin to perform any modification
    IF current_role = 'admin' OR auth.role() = 'service_role' THEN
        RETURN NEW;
    END IF;

    -- Block normal agents/users from modifying restricted verification fields
    IF (OLD.verification_status IS DISTINCT FROM NEW.verification_status) OR
       (OLD.rejection_reason IS DISTINCT FROM NEW.rejection_reason) OR
       (OLD.verified_at IS DISTINCT FROM NEW.verified_at) OR
       (OLD.verified_by IS DISTINCT FROM NEW.verified_by) THEN
        RAISE EXCEPTION 'Unauthorized: Only platform administrators can modify verification credentials.';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_guard_verification_mutation ON public.profiles;
CREATE TRIGGER trg_guard_verification_mutation
    BEFORE UPDATE ON public.profiles
    FOR EACH ROW
    EXECUTE FUNCTION public.check_agent_verification_mutation();

-- 4. Row Level Security (RLS) Policies on Profiles
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

-- Agents can read their own full profile
DROP POLICY IF EXISTS "Users can read own profile" ON public.profiles;
CREATE POLICY "Users can read own profile"
    ON public.profiles
    FOR SELECT
    TO authenticated
    USING (auth.uid() = id);

-- Admins can read all profiles (including queue)
DROP POLICY IF EXISTS "Admins can view all profiles" ON public.profiles;
CREATE POLICY "Admins can view all profiles"
    ON public.profiles
    FOR SELECT
    TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.profiles
            WHERE id = auth.uid() AND role = 'admin'
        )
    );

-- Admins can update any profile (approvals / rejections)
DROP POLICY IF EXISTS "Admins can update verification on all profiles" ON public.profiles;
CREATE POLICY "Admins can update verification on all profiles"
    ON public.profiles
    FOR UPDATE
    TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.profiles
            WHERE id = auth.uid() AND role = 'admin'
        )
    )
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.profiles
            WHERE id = auth.uid() AND role = 'admin'
        )
    );

-- 5. Public-Facing Safe Discovery View
-- Strips sensitive business information (tin_number, document_url) and only displays approved agents
CREATE OR REPLACE VIEW public.public_agent_directory AS
SELECT 
    id,
    name,
    business_name,
    avatar_url,
    phone,
    email,
    verification_status,
    verified_at,
    created_at
FROM public.profiles
WHERE role = 'agent' AND verification_status = 'approved';

GRANT SELECT ON public.public_agent_directory TO anon, authenticated;

-- 6. Storage Bucket & Policies for Business Documents
-- Create business-documents private bucket
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
    'business-documents',
    'business-documents',
    false,
    5242880, -- 5 MB
    ARRAY['application/pdf', 'image/jpeg', 'image/png']
)
ON CONFLICT (id) DO UPDATE SET
    public = false,
    file_size_limit = 5242880,
    allowed_mime_types = ARRAY['application/pdf', 'image/jpeg', 'image/png'];

-- Storage RLS: Agents can upload to their own folder: business-documents/{auth.uid()}/*
DROP POLICY IF EXISTS "Agents can upload own business documents" ON storage.objects;
CREATE POLICY "Agents can upload own business documents"
    ON storage.objects
    FOR INSERT
    TO authenticated
    WITH CHECK (
        bucket_id = 'business-documents' AND
        (storage.foldername(name))[1] = auth.uid()::text
    );

-- Storage RLS: Agents can read only their own documents
DROP POLICY IF EXISTS "Agents can read own business documents" ON storage.objects;
CREATE POLICY "Agents can read own business documents"
    ON storage.objects
    FOR SELECT
    TO authenticated
    USING (
        bucket_id = 'business-documents' AND
        (storage.foldername(name))[1] = auth.uid()::text
    );

-- Storage RLS: Platform Admins can read all business documents for verification
DROP POLICY IF EXISTS "Admins can view all business documents" ON storage.objects;
CREATE POLICY "Admins can view all business documents"
    ON storage.objects
    FOR SELECT
    TO authenticated
    USING (
        bucket_id = 'business-documents' AND
        EXISTS (
            SELECT 1 FROM public.profiles
            WHERE id = auth.uid() AND role = 'admin'
        )
    );
