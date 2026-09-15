-- ==============================================================================
-- SQL MIGRATION: 20260905000000_init_schema.sql
-- FASE 1: Fundación Técnica (Día 10) - Catálogos de la Rama Judicial de Colombia
-- DISEÑO: Arquitectura Modular, Alta Integridad y Desempeño Relacional (PostgreSQL)
-- ==============================================================================

BEGIN;

-- ------------------------------------------------------------------------------
-- 0. EXTENSIONES Y SEGURIDAD PREVENTIVA
-- ------------------------------------------------------------------------------
-- Aseguramos la existencia de la extensión para generación de UUIDs si es necesaria.
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ------------------------------------------------------------------------------
-- 1. FUNCIÓN DISPARADORA (TRIGGER) PARA ACTUALIZACIÓN AUTOMÁTICA DE TIMESTAMP
-- ------------------------------------------------------------------------------
-- Evita lógica duplicada de actualización de marcas de tiempo en el backend.
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ------------------------------------------------------------------------------
-- 2. TABLA: legal_areas (Áreas del Derecho / Catálogo Global)
-- ------------------------------------------------------------------------------
-- Define las jurisdicciones o áreas lógicas de la Rama Judicial colombiana.
-- Usamos un identificador numérico incremental secuencial (SMALLINT/INT) dado que
-- es un catálogo maestro estático nacional y ofrece un desempeño superior en índices.
CREATE TABLE IF NOT EXISTS public.legal_areas (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    code VARCHAR(10) NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc'::text, NOW()) NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc'::text, NOW()) NOT NULL,
    
    -- Restricciones de integridad y seguridad de datos
    CONSTRAINT uq_legal_areas_name UNIQUE (name),
    CONSTRAINT uq_legal_areas_code UNIQUE (code),
    CONSTRAINT chk_legal_areas_code_format CHECK (code ~ '^[A-Z0-9]+$') -- Código alfanumérico limpio
);

-- Comentarios explicativos para el autodescubrimiento y diccionarios de datos
COMMENT ON TABLE public.legal_areas IS 'Catálogo global maestro de áreas o jurisdicciones del derecho de la Rama Judicial de Colombia.';
COMMENT ON COLUMN public.legal_areas.id IS 'Identificador secuencial óptimo para relaciones referenciales rápidas.';
COMMENT ON COLUMN public.legal_areas.name IS 'Nombre representativo del área (ej. Civil, Laboral, Penal, Administrativo, Familia).';
COMMENT ON COLUMN public.legal_areas.code IS 'Código estándar de homologación judicial colombiano.';

-- Trigger de actualización temporal
CREATE TRIGGER trigger_update_legal_areas_updated_at
    BEFORE UPDATE ON public.legal_areas
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- ------------------------------------------------------------------------------
-- 3. TABLA: proceedings_types (Tipos de Actuaciones Judiciales / Catálogo Global)
-- ------------------------------------------------------------------------------
-- Modela de forma relacional el catálogo de actuaciones colombianas asociadas a
-- un área de derecho específica, garantizando integridad referencial estricta.
CREATE TABLE IF NOT EXISTS public.proceedings_types (
    id SERIAL PRIMARY KEY,
    legal_area_id INTEGER NOT NULL,
    name VARCHAR(150) NOT NULL,
    code VARCHAR(10),
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc'::text, NOW()) NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc'::text, NOW()) NOT NULL,

    -- Restricciones de integridad referencial y de dominio
    CONSTRAINT fk_proceedings_types_legal_area
        FOREIGN KEY (legal_area_id)
        REFERENCES public.legal_areas(id)
        ON DELETE RESTRICT, -- Impide borrar áreas si tienen actuaciones activas
    CONSTRAINT uq_proceedings_types_area_name UNIQUE (legal_area_id, name), -- Evita duplicidad lógica interna
    CONSTRAINT chk_proceedings_types_code_format CHECK (code IS NULL OR code ~ '^[A-Z0-9]+$')
);

COMMENT ON TABLE public.proceedings_types IS 'Catálogo de tipos de actuaciones judiciales homologadas, dependiente de las áreas del derecho.';
COMMENT ON COLUMN public.proceedings_types.legal_area_id IS 'Llave foránea hacia el área de derecho matriz.';
COMMENT ON COLUMN public.proceedings_types.name IS 'Nombre de la actuación (ej. Auto Admisorio, Contestación de Demanda, Sentencia, Recurso de Reposición).';
COMMENT ON COLUMN public.proceedings_types.code IS 'Código alfanumérico de homologación procedimental colombiana.';

CREATE TRIGGER trigger_update_proceedings_types_updated_at
    BEFORE UPDATE ON public.proceedings_types
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- ------------------------------------------------------------------------------
-- 4. ÍNDICES DE DESEMPEÑO (PERFORMANCE TUNING)
-- ------------------------------------------------------------------------------
-- Creamos índices explícitos sobre las llaves foráneas para optimizar la velocidad
-- de las operaciones JOIN y búsquedas de metadatos en la base de datos.
CREATE INDEX IF NOT EXISTS idx_proceedings_types_legal_area_id ON public.proceedings_types(legal_area_id);
CREATE INDEX IF NOT EXISTS idx_legal_areas_active ON public.legal_areas(is_active) WHERE is_active = TRUE;
CREATE INDEX IF NOT EXISTS idx_proceedings_types_active ON public.proceedings_types(is_active) WHERE is_active = TRUE;

-- ------------------------------------------------------------------------------
-- 5. PREPARACIÓN ESTRUCTURAL DE LA FASE 2: TABLA DE TENANTS (firms)
-- ------------------------------------------------------------------------------
-- Aunque la Fase 2 arranca formalmente en el Día 12, creamos la tabla principal de
-- inquilinos para que la base de datos sea estructuralmente coherente y Luis pueda
-- validar el entorno reproducible de forma integral en el Día 11.
CREATE TABLE IF NOT EXISTS public.firms (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    name VARCHAR(200) NOT NULL,
    nit VARCHAR(20) NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc'::text, NOW()) NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc'::text, NOW()) NOT NULL,

    CONSTRAINT uq_firms_nit UNIQUE (nit),
    CONSTRAINT chk_firms_nit_format CHECK (nit ~ '^[0-9]+-[0-9]$') -- Formato estándar de NIT colombiano (ej: 901234567-1)
);

COMMENT ON TABLE public.firms IS 'Entidad inquilina principal (Tenant) que define la frontera de aislamiento de datos.';
COMMENT ON COLUMN public.firms.id IS 'Identificador único global (UUID v4) para evitar colisiones entre firmas.';
COMMENT ON COLUMN public.firms.nit IS 'NIT (Número de Identificación Tributaria) único de la firma en Colombia.';

CREATE TRIGGER trigger_update_firms_updated_at
    BEFORE UPDATE ON public.firms
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

COMMIT;
