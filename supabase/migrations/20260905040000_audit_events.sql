-- =============================================================================
-- SQL MIGRATION: 20260905040000_audit_events.sql
-- FASE 2: Backend Multi-Tenant (Día 15) - Auditoría Inmutable de Eventos Críticos
-- ARQUITECTURA: Registro Inalterable, Triggers Automáticos y RLS Append-Only
-- =============================================================================

BEGIN;

-- -----------------------------------------------------------------------------
-- 1. TABLA: audit_events (Registro de Auditoría Inmutable)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.audit_events (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    firm_id UUID NOT NULL REFERENCES public.firms(id) ON DELETE CASCADE,
    user_id UUID REFERENCES public.user_profiles(id) ON DELETE SET NULL,
    action VARCHAR(100) NOT NULL, -- ej. 'auth:login', 'term:status_changed', 'term:cancelled', 'document:download'
    entity_type VARCHAR(100) NOT NULL, -- ej. 'term', 'document', 'case', 'session'
    entity_id UUID,
    payload_before JSONB,
    payload_after JSONB,
    ip_address VARCHAR(45),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc'::text, NOW()) NOT NULL
);

COMMENT ON TABLE public.audit_events IS 'Bitácora inalterable de auditoría para rastrear eventos de seguridad, términos procesales y documentos.';

-- Índices de rendimiento para consultas de auditoría por firma, usuario y fecha
CREATE INDEX IF NOT EXISTS idx_audit_events_firm_id ON public.audit_events(firm_id);
CREATE INDEX IF NOT EXISTS idx_audit_events_user_id ON public.audit_events(user_id);
CREATE INDEX IF NOT EXISTS idx_audit_events_action ON public.audit_events(action);
CREATE INDEX IF NOT EXISTS idx_audit_events_created_at ON public.audit_events(created_at DESC);

-- -----------------------------------------------------------------------------
-- 2. FUNCIÓN DE TRIGGER: log_deadline_changes()
-- -----------------------------------------------------------------------------
-- Registra automáticamente en audit_events cualquier cambio de estado o fecha en la tabla deadlines
CREATE OR REPLACE FUNCTION public.log_deadline_changes()
RETURNS TRIGGER AS $$
DECLARE
    v_user_id UUID := auth.uid();
BEGIN
    IF (TG_OP = 'UPDATE') THEN
        -- Registrar únicamente si hubo cambios relevantes en estado o fecha límite
        IF (OLD.status IS DISTINCT FROM NEW.status OR OLD.due_date IS DISTINCT FROM NEW.due_date) THEN
            INSERT INTO public.audit_events (
                firm_id,
                user_id,
                action,
                entity_type,
                entity_id,
                payload_before,
                payload_after
            ) VALUES (
                NEW.firm_id,
                v_user_id,
                CASE 
                    WHEN NEW.status = 'cancelled' THEN 'term:cancelled'
                    WHEN NEW.status = 'completed' THEN 'term:completed'
                    ELSE 'term:updated'
                END,
                'term',
                NEW.id,
                jsonb_build_object('status', OLD.status, 'due_date', OLD.due_date, 'title', OLD.title),
                jsonb_build_object('status', NEW.status, 'due_date', NEW.due_date, 'title', NEW.title)
            );
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- Trigger sobre la tabla deadlines
DROP TRIGGER IF EXISTS trg_audit_deadline_changes ON public.deadlines;
CREATE TRIGGER trg_audit_deadline_changes
    AFTER UPDATE ON public.deadlines
    FOR EACH ROW
    EXECUTE FUNCTION public.log_deadline_changes();

-- -----------------------------------------------------------------------------
-- 3. HABILITACIÓN DE RLS Y POLÍTICAS DE INMUTABILIDAD (APPEND-ONLY)
-- -----------------------------------------------------------------------------
ALTER TABLE public.audit_events ENABLE ROW LEVEL SECURITY;

-- A. Lectura (SELECT): Los miembros de la firma pueden consultar la bitácora de su propia firma
DROP POLICY IF EXISTS select_audit_events ON public.audit_events;
CREATE POLICY select_audit_events ON public.audit_events
    FOR SELECT
    USING (firm_id = public.get_current_tenant_id());

-- B. Inserción (INSERT): Permitida para registrar eventos pertenecientes a la propia firma
DROP POLICY IF EXISTS insert_audit_events ON public.audit_events;
CREATE POLICY insert_audit_events ON public.audit_events
    FOR INSERT
    WITH CHECK (firm_id = public.get_current_tenant_id());

-- C. Modificación (UPDATE): ESTRICTAMENTE PROHIBIDA (Sin política UPDATE = Deny-by-default)
-- D. Eliminación (DELETE): ESTRICTAMENTE PROHIBIDA (Sin política DELETE = Deny-by-default)

COMMIT;
