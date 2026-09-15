-- ============================================================================= 
-- PRUEBA ADVERSARIAL RLS CORREGIDA (FORZANDO ROL AUTHENTICATED) 
-- ============================================================================= 
BEGIN; 

-- 1\. Asegurar la existencia de datos de prueba (Firma A y Firma B) 
INSERT INTO public.firms (id, name, nit) VALUES ('a0000000-0000-0000-0000-000000000001', 'Firma Abogados A', '12345678-9'), ('b0000000-0000-0000-0000-000000000002', 'Firma Abogados B', '12345678-0') ON CONFLICT (id) DO NOTHING; INSERT INTO public.user_profiles (id, first_name, last_name, email) VALUES ('a1111111-1111-1111-1111-111111111111', 'Abogado', 'Firma A', 'abogado.a@firm.com'), ('b2222222-2222-2222-2222-222222222222', 'Abogado', 'Firma B', 'abogado.b@firm.com') ON CONFLICT (id) DO NOTHING; INSERT INTO public.firm_members (firm_id, user_id, role_id) VALUES ('a0000000-0000-0000-0000-000000000001', 'a1111111-1111-1111-1111-111111111111', 'lawyer'), ('b0000000-0000-0000-0000-000000000002', 'b2222222-2222-2222-2222-222222222222', 'lawyer') ON CONFLICT DO NOTHING; INSERT INTO public.cases (id, firm_id, case_number, title) VALUES ('c1111111-1111-1111-1111-111111111111', 'a0000000-0000-0000-0000-000000000001', 'EXP-001', 'Expediente Confidencial Firma A'), ('c2222222-2222-2222-2222-222222222222', 'b0000000-0000-0000-0000-000000000002', 'EXP-002', 'Expediente Confidencial Firma B') ON CONFLICT DO NOTHING; 

-- 2\. ¡PASO CRÍTICO! Cambiar el rol de sesión a 'authenticated' 
-- Esto deshabilita el 'Bypass RLS' del superusuario postgres para esta transacción. 
SET LOCAL ROLE authenticated; 

-- 3\. Inyectar los claims JWT del Abogado de la Firma A 
SET LOCAL request.jwt.claims = '{"sub": "a1111111-1111-1111-1111-111111111111", "role": "authenticated"}'; 

-- 4\. Ejecutar la consulta sin filtros 
SELECT id, case_number, title FROM public.cases; 

-- 5\. Revertir cambios de prueba 
ROLLBACK;