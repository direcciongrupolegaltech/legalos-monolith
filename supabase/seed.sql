-- ==============================================================================
-- SQL SEED: seed.sql
-- FASE 1: Fundación Técnica (Día 10) - Semillas de Datos de Prueba Locales
-- DISEÑO: Datos realistas para Colombia y preparación del aislamiento de firmas
-- ==============================================================================

BEGIN;

-- ------------------------------------------------------------------------------
-- 1. POBLAR ÁREAS DEL DERECHO (legal_areas)
-- ------------------------------------------------------------------------------
INSERT INTO public.legal_areas (name, code, is_active) VALUES
('Civil', 'CIV', true),
('Administrativo', 'ADM', true),
('Laboral', 'LAB', true),
('Penal', 'PEN', true),
('Familia', 'FAM', true)
ON CONFLICT (name) DO UPDATE SET is_active = EXCLUDED.is_active;

-- ------------------------------------------------------------------------------
-- 2. POBLAR TIPOS DE ACTUACIONES JUDICIALES (proceedings_types)
-- ------------------------------------------------------------------------------
-- Obtenemos los IDs insertados para asociarlos con precisión quirúrgica.
INSERT INTO public.proceedings_types (legal_area_id, name, code, is_active) VALUES
-- Actuaciones en Área Civil
((SELECT id FROM public.legal_areas WHERE code = 'CIV'), 'Auto Admisorio de Demanda', 'CIV001', true),
((SELECT id FROM public.legal_areas WHERE code = 'CIV'), 'Contestación de Demanda', 'CIV002', true),
((SELECT id FROM public.legal_areas WHERE code = 'CIV'), 'Fijación de Litigio', 'CIV003', true),
((SELECT id FROM public.legal_areas WHERE code = 'CIV'), 'Sentencia de Primera Instancia', 'CIV004', true),
((SELECT id FROM public.legal_areas WHERE code = 'CIV'), 'Recurso de Apelación', 'CIV005', true),

-- Actuaciones en Área Administrativa
((SELECT id FROM public.legal_areas WHERE code = 'ADM'), 'Auto que Rechaza la Demanda', 'ADM001', true),
((SELECT id FROM public.legal_areas WHERE code = 'ADM'), 'Audiencia Inicial (Art. 180 CPACA)', 'ADM002', true),
((SELECT id FROM public.legal_areas WHERE code = 'ADM'), 'Presentación de Alegatos de Conclusión', 'ADM003', true),
((SELECT id FROM public.legal_areas WHERE code = 'ADM'), 'Fallo Definitivo', 'ADM004', true),

-- Actuaciones en Área Laboral
((SELECT id FROM public.legal_areas WHERE code = 'LAB'), 'Audiencia de Conciliación, Decisión de Excepciones Previas, Saneamiento y Fijación de Litigio', 'LAB001', true),
((SELECT id FROM public.legal_areas WHERE code = 'LAB'), 'Radicación de Demanda', 'LAB002', true),
((SELECT id FROM public.legal_areas WHERE code = 'LAB'), 'Alegato de Conclusión Verbal', 'LAB003', true),

-- Actuaciones en Área Penal
((SELECT id FROM public.legal_areas WHERE code = 'PEN'), 'Audiencia de Formulación de Imputación', 'PEN001', true),
((SELECT id FROM public.legal_areas WHERE code = 'PEN'), 'Audiencia Preparatoria', 'PEN002', true),
((SELECT id FROM public.legal_areas WHERE code = 'PEN'), 'Juicio Oral', 'PEN003', true),
((SELECT id FROM public.legal_areas WHERE code = 'PEN'), 'Lectura de Fallo / Sentencia', 'PEN004', true),

-- Actuaciones en Área de Familia
((SELECT id FROM public.legal_areas WHERE code = 'FAM'), 'Auto de Medidas Cautelares', 'FAM001', true),
((SELECT id FROM public.legal_areas WHERE code = 'FAM'), 'Audiencia de Pruebas y Fallo', 'FAM002', true)
ON CONFLICT (legal_area_id, name) DO NOTHING;

-- ------------------------------------------------------------------------------
-- 3. POBLAR FIRMAS DEMO (firms - Preparación de Ambiente Multi-tenant)
-- ------------------------------------------------------------------------------
-- Creamos dos firmas independientes con NITs colombianos válidos para las
-- futuras simulaciones y pruebas adversariales de aislamiento.
INSERT INTO public.firms (id, name, nit, is_active) VALUES
('a3b047ee-696e-4f7f-8e4a-9e32a6881c10', 'García & Asociados Consultores', '901345678-1', true),
('b8f21919-45cb-4bc1-90a2-2dca11f2fa41', 'Restrepo & Alianzas Legales', '900765432-8', true)
ON CONFLICT (nit) DO UPDATE SET name = EXCLUDED.name;

COMMIT;
