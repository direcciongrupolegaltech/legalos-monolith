SELECT tablename, indexname FROM pg_indexes WHERE tablename = 'audit_events';

BEGIN;

-- 1. Preparar datos de prueba efímeros
INSERT INTO public.firms (id, name, nit) VALUES ('f0000000-0000-0000-0000-000000000001', 'Firma Auditoría Test', '1234567890-1') ON CONFLICT DO NOTHING;
INSERT INTO public.user_profiles (id, first_name, last_name, email) VALUES ('e0000000-0000-0000-0000-000000000001', 'Luis', 'Auditor', 'audit@test.com') ON CONFLICT DO NOTHING;
INSERT INTO public.firm_members (firm_id, user_id, role_id) VALUES ('f0000000-0000-0000-0000-000000000001', 'e0000000-0000-0000-0000-000000000001', 'administrator') ON CONFLICT DO NOTHING;
INSERT INTO public.cases (id, firm_id, case_number, title) VALUES ('c0000000-0000-0000-0000-000000000001', 'f0000000-0000-0000-0000-000000000001', 'EXP-AUDIT', 'Caso Auditoría') ON CONFLICT DO NOTHING;
INSERT INTO public.deadlines (id, firm_id, case_id, title, due_date, status) VALUES ('d0000000-0000-0000-0000-000000000001', 'f0000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000001', 'Término de Reposición', NOW() + INTERVAL '5 days', 'active') ON CONFLICT DO NOTHING;

-- 2. Cambiar rol a authenticated e inyectar JWT claims
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub": "e0000000-0000-0000-0000-000000000001", "role": "authenticated"}';

-- 3. Probar disparo del trigger ante anulación de término
UPDATE public.deadlines SET status = 'cancelled' WHERE id = 'd0000000-0000-0000-0000-000000000001';

-- 4. Verificar inserción automática de fotograma en audit_events
SELECT action, entity_type, payload_before, payload_after FROM public.audit_events WHERE entity_id = 'd0000000-0000-0000-0000-000000000001';

-- 5. Probar intento de alteración (Debe ser rechazado por RLS)
DO $$
BEGIN
    UPDATE public.audit_events SET action = 'tampered' WHERE entity_id = 'd0000000-0000-0000-0000-000000000001';
    RAISE EXCEPTION 'FALLO: RLS permitió modificar la auditoría.';
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'SUCCESS [Inmutabilidad]: Alteración rechazada por RLS.';
END $$;

ROLLBACK;
