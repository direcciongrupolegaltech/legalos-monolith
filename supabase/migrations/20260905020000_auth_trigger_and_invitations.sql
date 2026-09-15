-- ==============================================================================
-- SQL MIGRATION: 20260905020000_auth_trigger_and_invitations.sql
-- FASE 2: Backend Multi-Tenant (Día 13) - Trigger Sincronizador y Tabla de Invitaciones
-- ==============================================================================

BEGIN;

-- ------------------------------------------------------------------------------
-- 1. FUNCIÓN Y TRIGGER DE SINCRONIZACIÓN AUTOMÁTICA DE USUARIOS
-- ------------------------------------------------------------------------------
-- Sincroniza la creación de cuentas en auth.users hacia public.user_profiles.
-- Uso de SECURITY DEFINER y SET search_path para garantizar la ejecución segura
-- con privilegios de sistema e inmune a vulnerabilidades de search_path hijacking.

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO public.user_profiles (
        id,
        first_name,
        last_name,
        email,
        is_active
    ) VALUES (
        NEW.id,
        COALESCE(NEW.raw_user_meta_data->>'first_name', 'Nombre'),
        COALESCE(NEW.raw_user_meta_data->>'last_name', 'Apellido'),
        NEW.email,
        TRUE
    )
    ON CONFLICT (id) DO UPDATE SET
        email = EXCLUDED.email,
        updated_at = TIMEZONE('utc'::text, NOW());

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth;

COMMENT ON FUNCTION public.handle_new_user() IS 'Trigger transaccional para sincronizar nuevos usuarios de Supabase Auth con public.user_profiles.';

-- Creación del Trigger sobre el esquema protegido auth
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;

CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW
    EXECUTE FUNCTION public.handle_new_user();

-- ------------------------------------------------------------------------------
-- 2. TABLA DE INVITACIONES MULTI-TENANT: firm_invitations
-- ------------------------------------------------------------------------------
-- Gestiona el flujo seguro de invitaciones temporales mediante tokens unívocos.

CREATE TABLE IF NOT EXISTS public.firm_invitations (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    firm_id UUID NOT NULL,
    email VARCHAR(255) NOT NULL,
    role_id VARCHAR(50) NOT NULL,
    token VARCHAR(100) NOT NULL,
    invited_by UUID NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'pending',
    expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc'::text, NOW()) NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc'::text, NOW()) NOT NULL,

    CONSTRAINT fk_firm_invitations_firm
        FOREIGN KEY (firm_id)
        REFERENCES public.firms(id)
        ON DELETE CASCADE,
    CONSTRAINT fk_firm_invitations_role
        FOREIGN KEY (role_id)
        REFERENCES public.roles(id)
        ON DELETE RESTRICT,
    CONSTRAINT fk_firm_invitations_invited_by
        FOREIGN KEY (invited_by)
        REFERENCES public.user_profiles(id)
        ON DELETE CASCADE,
    CONSTRAINT uq_firm_invitations_token UNIQUE (token),
    CONSTRAINT chk_firm_invitations_status CHECK (status IN ('pending', 'accepted', 'expired', 'revoked')),
    CONSTRAINT chk_firm_invitations_email CHECK (email ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$')
);

COMMENT ON TABLE public.firm_invitations IS 'Registro de invitaciones pendientes y procesadas para unirse a firmas en LegalOS.';

CREATE INDEX IF NOT EXISTS idx_firm_invitations_token ON public.firm_invitations(token);
CREATE INDEX IF NOT EXISTS idx_firm_invitations_firm_id ON public.firm_invitations(firm_id);
CREATE INDEX IF NOT EXISTS idx_firm_invitations_email ON public.firm_invitations(email);

-- Trigger de timestamp automático
CREATE TRIGGER trigger_update_firm_invitations_updated_at
    BEFORE UPDATE ON public.firm_invitations
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- ------------------------------------------------------------------------------
-- 3. POLÍTICAS RLS EN firm_invitations
-- ------------------------------------------------------------------------------
ALTER TABLE public.firm_invitations ENABLE ROW LEVEL SECURITY;

-- Los administradores de la firma pueden consultar las invitaciones emitidas por su firma
CREATE POLICY select_firm_invitations ON public.firm_invitations
    FOR SELECT
    USING (
        firm_id = public.get_current_tenant_id() OR
        email = (SELECT email FROM public.user_profiles WHERE id = auth.uid())
    );

-- Solo administradores pueden crear invitaciones en su propia firma
CREATE POLICY insert_firm_invitations ON public.firm_invitations
    FOR INSERT
    WITH CHECK (
        firm_id = public.get_current_tenant_id() AND
        EXISTS (
            SELECT 1 FROM public.firm_members fm
            WHERE fm.user_id = auth.uid()
              AND fm.firm_id = firm_id
              AND fm.role_id = 'administrator'
        )
    );

-- Solo administradores o el usuario invitado pueden actualizar el estado de la invitación
CREATE POLICY update_firm_invitations ON public.firm_invitations
    FOR UPDATE
    USING (
        firm_id = public.get_current_tenant_id() OR
        email = (SELECT email FROM public.user_profiles WHERE id = auth.uid())
    );

COMMIT;
