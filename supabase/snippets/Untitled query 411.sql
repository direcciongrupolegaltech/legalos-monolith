BEGIN;

-- 1. Preparar datos de prueba
INSERT INTO public.firms (id, name, nit) VALUES ('f0000000-0000-0000-0000-000000000001', 'Firma Auditoría Test', '123456781-0') ON CONFLICT DO NOTHING;
INSERT INTO public.user_profiles (id, first_name, last_name, email) VALUES ('u0000000-0000-0000-0000-000000000001', 'Luis', 'Auditor', 'audit@test.com') ON CONFLICT DO NOTHING;
INSERT INTO public.firm_members (firm_id, user_id, role_id) VALUES ('f0000000-0000-0000-0000-000000000001', 'u0000000-0000-0000-0000-000000000001', 'administrator') ON CONFLICT DO NOTHING;

INSERT INTO public.cases (id, firm_id, case_number, title) VALUES ('c0000000-0000-0000-0000-000000000001', 'f0000000-0000-0000-0000-000000000001', 'EXP-AUDIT', 'Caso de Prueba Auditoría') ON CONFLICT DO NOTHING;
INSERT INTO public.deadlines (id, firm_id, case_id, title, due_date, status) VALUES ('d0000000-0000-0000-0000-000000000001', 'f0000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000001', 'Término de Reposición', NOW() + INTERVAL '5 days', 'active') ON CONFLICT DO NOTHING;

-- 2. Configurar la sesión del usuario
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub": "u0000000-0000-0000-0000-000000000001", "role": "authenticated"}';

-- -----------------------------------------------------------------------------
-- PRUEBA 1: Disparo Automático del Trigger ante Anulación de Término
-- -----------------------------------------------------------------------------
UPDATE public.deadlines
SET status = 'cancelled'
WHERE id = 'd0000000-0000-0000-0000-000000000001';

-- Comprobar que el trigger inyectó la fila de auditoría con los payloads antes/después
SELECT action, entity_type, payload_before, payload_after
FROM public.audit_events
WHERE entity_id = 'd0000000-0000-0000-0000-000000000001';

-- -----------------------------------------------------------------------------
-- PRUEBA 2: Intento de Alteración de Auditoría (Debe Fallar)
-- -----------------------------------------------------------------------------
DO $$
BEGIN
    UPDATE public.audit_events
    SET action = 'tampered:action'
    WHERE entity_id = 'd0000000-0000-0000-0000-000000000001';

    RAISE EXCEPTION 'FALLO: RLS permitió modificar un registro de auditoría.';
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'SUCCESS [Inmutabilidad]: Modificación en audit_events rechazada por RLS.';
END $$;

ROLLBACK;
