-- =============================================================================
-- SQL MIGRATION: 20260905030000_rls_policies_and_tenant_injection.sql
-- FASE 2: Backend Multi-Tenant (Día 14) - RLS e Inyección de Tenant ID
-- ARQUITECTURA: Confianza Cero (Zero-Trust), Inyección Automática de Tenant y RBAC
-- =============================================================================

BEGIN;

-- -----------------------------------------------------------------------------
-- 1. FUNCIÓN DE SEGURIDAD RECURSION-FREE: get_current_tenant_id()
-- -----------------------------------------------------------------------------
-- Retorna el firm_id asociado al usuario autenticado (auth.uid()).
-- Usa SECURITY DEFINER y search_path seguro para evitar bucles infinitos en RLS.
CREATE OR REPLACE FUNCTION public.get_current_tenant_id()
RETURNS UUID AS $$
DECLARE
    v_firm_id UUID;
BEGIN
    IF auth.uid() IS NULL THEN
        RETURN NULL;
    END IF;

    SELECT fm.firm_id INTO v_firm_id
    FROM public.firm_members fm
    WHERE fm.user_id = auth.uid() 
      AND fm.is_active = TRUE
    LIMIT 1;
    
    RETURN v_firm_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

COMMENT ON FUNCTION public.get_current_tenant_id() IS 'Obtiene de manera segura y sin recursividad el ID de la firma (tenant) activa del usuario autenticado.';

-- -----------------------------------------------------------------------------
-- 2. FUNCIÓN AUXILIAR DE ROL: has_firm_role()
-- -----------------------------------------------------------------------------
-- Valida si el usuario autenticado posee un rol específico dentro de una firma.
CREATE OR REPLACE FUNCTION public.has_firm_role(p_firm_id UUID, p_role_id VARCHAR)
RETURNS BOOLEAN AS $$
BEGIN
    IF auth.uid() IS NULL OR p_firm_id IS NULL THEN
        RETURN FALSE;
    END IF;

    RETURN EXISTS (
        SELECT 1 
        FROM public.firm_members fm
        WHERE fm.firm_id = p_firm_id
          AND fm.user_id = auth.uid()
          AND fm.role_id = p_role_id
          AND fm.is_active = TRUE
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

COMMENT ON FUNCTION public.has_firm_role(UUID, VARCHAR) IS 'Verifica de forma aislada si el usuario tiene un rol determinado en la firma objetivo.';

-- -----------------------------------------------------------------------------
-- 3. ESTRUCTURA LÓGICA DE TABLAS DE DOMINIO (SI NO EXISTEN)
-- -----------------------------------------------------------------------------

-- A. Tabla de Firmas (Tenant Principal)
CREATE TABLE IF NOT EXISTS public.firms (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    name VARCHAR(200) NOT NULL,
    tax_id VARCHAR(50) UNIQUE,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc'::text, NOW()) NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc'::text, NOW()) NOT NULL
);

-- B. Tabla de Expedientes (Cases)
CREATE TABLE IF NOT EXISTS public.cases (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    firm_id UUID NOT NULL REFERENCES public.firms(id) ON DELETE CASCADE,
    case_number VARCHAR(100) NOT NULL,
    title VARCHAR(255) NOT NULL,
    description TEXT,
    status VARCHAR(50) NOT NULL DEFAULT 'active',
    created_by UUID REFERENCES public.user_profiles(id) ON DELETE SET NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc'::text, NOW()) NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc'::text, NOW()) NOT NULL,

    CONSTRAINT uq_cases_firm_case_number UNIQUE (firm_id, case_number)
);

-- C. Tabla de Actuaciones Procesales (Proceedings)
CREATE TABLE IF NOT EXISTS public.proceedings (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    firm_id UUID NOT NULL REFERENCES public.firms(id) ON DELETE CASCADE,
    case_id UUID NOT NULL REFERENCES public.cases(id) ON DELETE CASCADE,
    title VARCHAR(255) NOT NULL,
    content TEXT NOT NULL,
    proceeding_date TIMESTAMP WITH TIME ZONE NOT NULL,
    created_by UUID REFERENCES public.user_profiles(id) ON DELETE SET NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc'::text, NOW()) NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc'::text, NOW()) NOT NULL
);

-- D. Tabla de Términos Procesales (Deadlines / Alert System)
CREATE TABLE IF NOT EXISTS public.deadlines (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    firm_id UUID NOT NULL REFERENCES public.firms(id) ON DELETE CASCADE,
    case_id UUID NOT NULL REFERENCES public.cases(id) ON DELETE CASCADE,
    proceeding_id UUID REFERENCES public.proceedings(id) ON DELETE SET NULL,
    title VARCHAR(255) NOT NULL,
    due_date TIMESTAMP WITH TIME ZONE NOT NULL,
    status VARCHAR(50) NOT NULL DEFAULT 'active', -- active, completed, cancelled
    created_by UUID REFERENCES public.user_profiles(id) ON DELETE SET NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc'::text, NOW()) NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc'::text, NOW()) NOT NULL,

    CONSTRAINT chk_deadlines_status CHECK (status IN ('active', 'completed', 'cancelled'))
);

-- E. Tabla de Documentos Adosados (Documents)
CREATE TABLE IF NOT EXISTS public.documents (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    firm_id UUID NOT NULL REFERENCES public.firms(id) ON DELETE CASCADE,
    case_id UUID NOT NULL REFERENCES public.cases(id) ON DELETE CASCADE,
    file_name VARCHAR(255) NOT NULL,
    file_path VARCHAR(500) NOT NULL,
    file_size INTEGER NOT NULL,
    mime_type VARCHAR(100) NOT NULL,
    created_by UUID REFERENCES public.user_profiles(id) ON DELETE SET NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc'::text, NOW()) NOT NULL
);

-- -----------------------------------------------------------------------------
-- 4. ÍNDICES DE COBERTURA MULTI-TENANT (ACCELERATED JOIN & FILTER)
-- -----------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_cases_firm_id ON public.cases(firm_id);
CREATE INDEX IF NOT EXISTS idx_proceedings_firm_id ON public.proceedings(firm_id);
CREATE INDEX IF NOT EXISTS idx_proceedings_case_id ON public.proceedings(case_id);
CREATE INDEX IF NOT EXISTS idx_deadlines_firm_id ON public.deadlines(firm_id);
CREATE INDEX IF NOT EXISTS idx_deadlines_case_id ON public.deadlines(case_id);
CREATE INDEX IF NOT EXISTS idx_documents_firm_id ON public.documents(firm_id);
CREATE INDEX IF NOT EXISTS idx_documents_case_id ON public.documents(case_id);

-- -----------------------------------------------------------------------------
-- 5. HABILITACIÓN DE ROW LEVEL SECURITY (RLS)
-- -----------------------------------------------------------------------------
ALTER TABLE public.firms ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cases ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.proceedings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.deadlines ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.documents ENABLE ROW LEVEL SECURITY;

-- -----------------------------------------------------------------------------
-- 6. POLÍTICAS RLS PARA FIRMS
-- -----------------------------------------------------------------------------
DROP POLICY IF EXISTS select_firms ON public.firms;
CREATE POLICY select_firms ON public.firms
    FOR SELECT
    USING (id = public.get_current_tenant_id());

DROP POLICY IF EXISTS update_firms ON public.firms;
CREATE POLICY update_firms ON public.firms
    FOR UPDATE
    USING (
        id = public.get_current_tenant_id() AND 
        public.has_firm_role(id, 'administrator')
    )
    WITH CHECK (
        id = public.get_current_tenant_id() AND 
        public.has_firm_role(id, 'administrator')
    );

-- -----------------------------------------------------------------------------
-- 7. POLÍTICAS RLS PARA CASES (EXPEDIENTES)
-- -----------------------------------------------------------------------------
DROP POLICY IF EXISTS select_cases ON public.cases;
CREATE POLICY select_cases ON public.cases
    FOR SELECT
    USING (firm_id = public.get_current_tenant_id());

DROP POLICY IF EXISTS insert_cases ON public.cases;
CREATE POLICY insert_cases ON public.cases
    FOR INSERT
    WITH CHECK (firm_id = public.get_current_tenant_id());

DROP POLICY IF EXISTS update_cases ON public.cases;
CREATE POLICY update_cases ON public.cases
    FOR UPDATE
    USING (firm_id = public.get_current_tenant_id())
    WITH CHECK (firm_id = public.get_current_tenant_id());

DROP POLICY IF EXISTS delete_cases ON public.cases;
CREATE POLICY delete_cases ON public.cases
    FOR DELETE
    USING (
        firm_id = public.get_current_tenant_id() AND 
        public.has_firm_role(firm_id, 'administrator')
    );

-- -----------------------------------------------------------------------------
-- 8. POLÍTICAS RLS PARA PROCEEDINGS (ACTUACIONES)
-- -----------------------------------------------------------------------------
DROP POLICY IF EXISTS select_proceedings ON public.proceedings;
CREATE POLICY select_proceedings ON public.proceedings
    FOR SELECT
    USING (firm_id = public.get_current_tenant_id());

DROP POLICY IF EXISTS insert_proceedings ON public.proceedings;
CREATE POLICY insert_proceedings ON public.proceedings
    FOR INSERT
    WITH CHECK (firm_id = public.get_current_tenant_id());

DROP POLICY IF EXISTS update_proceedings ON public.proceedings;
CREATE POLICY update_proceedings ON public.proceedings
    FOR UPDATE
    USING (firm_id = public.get_current_tenant_id())
    WITH CHECK (firm_id = public.get_current_tenant_id());

DROP POLICY IF EXISTS delete_proceedings ON public.proceedings;
CREATE POLICY delete_proceedings ON public.proceedings
    FOR DELETE
    USING (
        firm_id = public.get_current_tenant_id() AND 
        public.has_firm_role(firm_id, 'administrator')
    );

-- -----------------------------------------------------------------------------
-- 9. POLÍTICAS RLS PARA DEADLINES (TÉRMINOS)
-- -----------------------------------------------------------------------------
DROP POLICY IF EXISTS select_deadlines ON public.deadlines;
CREATE POLICY select_deadlines ON public.deadlines
    FOR SELECT
    USING (firm_id = public.get_current_tenant_id());

DROP POLICY IF EXISTS insert_deadlines ON public.deadlines;
CREATE POLICY insert_deadlines ON public.deadlines
    FOR INSERT
    WITH CHECK (firm_id = public.get_current_tenant_id());

DROP POLICY IF EXISTS update_deadlines ON public.deadlines;
CREATE POLICY update_deadlines ON public.deadlines
    FOR UPDATE
    USING (firm_id = public.get_current_tenant_id())
    WITH CHECK (firm_id = public.get_current_tenant_id());

DROP POLICY IF EXISTS delete_deadlines ON public.deadlines;
CREATE POLICY delete_deadlines ON public.deadlines
    FOR DELETE
    USING (
        firm_id = public.get_current_tenant_id() AND 
        public.has_firm_role(firm_id, 'administrator')
    );

-- -----------------------------------------------------------------------------
-- 10. POLÍTICAS RLS PARA DOCUMENTS (DOCUMENTOS)
-- -----------------------------------------------------------------------------
DROP POLICY IF EXISTS select_documents ON public.documents;
CREATE POLICY select_documents ON public.documents
    FOR SELECT
    USING (firm_id = public.get_current_tenant_id());

DROP POLICY IF EXISTS insert_documents ON public.documents;
CREATE POLICY insert_documents ON public.documents
    FOR INSERT
    WITH CHECK (firm_id = public.get_current_tenant_id());

DROP POLICY IF EXISTS update_documents ON public.documents;
CREATE POLICY update_documents ON public.documents
    FOR UPDATE
    USING (firm_id = public.get_current_tenant_id())
    WITH CHECK (firm_id = public.get_current_tenant_id());

DROP POLICY IF EXISTS delete_documents ON public.documents;
CREATE POLICY delete_documents ON public.documents
    FOR DELETE
    USING (
        firm_id = public.get_current_tenant_id() AND 
        public.has_firm_role(firm_id, 'administrator')
    );

COMMIT;
