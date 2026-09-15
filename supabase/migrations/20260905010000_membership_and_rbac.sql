-- ==============================================================================
-- SQL MIGRATION: 20260905010000_membership_and_rbac.sql
-- FASE 2: Backend Multi-Tenant (Día 12) - Estructura Organizacional y RBAC
-- DISEÑO: Arquitectura Multi-Tenant, Control de Acceso (RBAC) y Seguridad RLS
-- ==============================================================================

BEGIN;

-- ------------------------------------------------------------------------------
-- 1. TABLA: roles (Roles de la Plataforma)
-- ------------------------------------------------------------------------------
-- Almacena los perfiles funcionales del sistema. Usamos VARCHAR(50) como llave primaria
-- natural (ej. 'administrator', 'lawyer', 'assistant') para evitar joins costosos
-- en chequeos de sesión rápidos y facilitar la legibilidad del código.
CREATE TABLE IF NOT EXISTS public.roles (
    id VARCHAR(50) PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    description TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc'::text, NOW()) NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc'::text, NOW()) NOT NULL,

    CONSTRAINT chk_roles_id_format CHECK (id ~ '^[a-z_]+$') -- id en minúsculas y snake_case
);

COMMENT ON TABLE public.roles IS 'Roles del sistema (ej. administrator, lawyer, assistant) para el control de accesos.';
COMMENT ON COLUMN public.roles.id IS 'Identificador natural (snake_case) que sirve de clave única funcional.';

CREATE TRIGGER trigger_update_roles_updated_at
    BEFORE UPDATE ON public.roles
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- ------------------------------------------------------------------------------
-- 2. TABLA: permissions (Permisos del Sistema)
-- ------------------------------------------------------------------------------
-- Define las acciones granulares permitidas en la plataforma (ej. 'cases:create', 'terms:cancel').
CREATE TABLE IF NOT EXISTS public.permissions (
    id VARCHAR(100) PRIMARY KEY,
    name VARCHAR(150) NOT NULL,
    description TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc'::text, NOW()) NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc'::text, NOW()) NOT NULL,

    CONSTRAINT chk_permissions_id_format CHECK (id ~ '^[a-z_]+:[a-z_]+$') -- formato modulo:accion (ej. cases:create)
);

COMMENT ON TABLE public.permissions IS 'Permisos granulares que controlan las acciones específicas de la plataforma.';

CREATE TRIGGER trigger_update_permissions_updated_at
    BEFORE UPDATE ON public.permissions
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- ------------------------------------------------------------------------------
-- 3. TABLA: role_permissions (Matriz de Asociación de Roles y Permisos)
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.role_permissions (
    role_id VARCHAR(50) NOT NULL,
    permission_id VARCHAR(100) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc'::text, NOW()) NOT NULL,

    CONSTRAINT fk_role_permissions_role
        FOREIGN KEY (role_id)
        REFERENCES public.roles(id)
        ON DELETE CASCADE,
    CONSTRAINT fk_role_permissions_permission
        FOREIGN KEY (permission_id)
        REFERENCES public.permissions(id)
        ON DELETE CASCADE,
    CONSTRAINT pk_role_permissions PRIMARY KEY (role_id, permission_id)
);

COMMENT ON TABLE public.role_permissions IS 'Tabla relacional intermedia que asigna permisos granulares a cada rol.';

-- ------------------------------------------------------------------------------
-- 4. TABLA: user_profiles (Perfiles de Usuarios de LegalOS)
-- ------------------------------------------------------------------------------
-- Almacena los datos personales del usuario. Se vincula 1:1 con auth.users de Supabase Auth.
-- Nota: En Supabase Auth, la creación de usuarios ocurre en el esquema privado auth.
CREATE TABLE IF NOT EXISTS public.user_profiles (
    id UUID PRIMARY KEY, -- Coincide con auth.users.id
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100) NOT NULL,
    email VARCHAR(255) NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc'::text, NOW()) NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc'::text, NOW()) NOT NULL,

    CONSTRAINT uq_user_profiles_email UNIQUE (email),
    CONSTRAINT chk_user_profiles_email_format CHECK (email ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$')
);

COMMENT ON TABLE public.user_profiles IS 'Perfiles públicos de usuario vinculados directamente a la autenticación de Supabase.';
COMMENT ON COLUMN public.user_profiles.id IS 'Clave primaria vinculada a auth.users.id de Supabase Auth.';

CREATE TRIGGER trigger_update_user_profiles_updated_at
    BEFORE UPDATE ON public.user_profiles
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- ------------------------------------------------------------------------------
-- 5. TABLA: firm_members (Membresía e Inquilinos de Firmas Procesales)
-- ------------------------------------------------------------------------------
-- Resuelve la relación de membresía (muchos a muchos) de los usuarios con las firmas (tenants).
-- Garantiza el aislamiento al asociar un usuario específico a una firma con un rol determinado.
CREATE TABLE IF NOT EXISTS public.firm_members (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    firm_id UUID NOT NULL,
    user_id UUID NOT NULL,
    role_id VARCHAR(50) NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc'::text, NOW()) NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc'::text, NOW()) NOT NULL,

    CONSTRAINT fk_firm_members_firm
        FOREIGN KEY (firm_id)
        REFERENCES public.firms(id)
        ON DELETE CASCADE,
    CONSTRAINT fk_firm_members_user
        FOREIGN KEY (user_id)
        REFERENCES public.user_profiles(id)
        ON DELETE CASCADE,
    CONSTRAINT fk_firm_members_role
        FOREIGN KEY (role_id)
        REFERENCES public.roles(id)
        ON DELETE RESTRICT,
    CONSTRAINT uq_firm_members_firm_user UNIQUE (firm_id, user_id) -- Un usuario pertenece una sola vez a la misma firma
);

COMMENT ON TABLE public.firm_members IS 'Tabla de membresía que asocia usuarios con firmas (tenants) y les otorga un rol específico.';

CREATE TRIGGER trigger_update_firm_members_updated_at
    BEFORE UPDATE ON public.firm_members
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- ------------------------------------------------------------------------------
-- 6. ÍNDICES DE RENDIMIENTO Y RENDIMIENTO DE ACCESO MULTI-TENANT
-- ------------------------------------------------------------------------------
-- Se indexan las llaves foráneas para optimizar búsquedas frecuentes en el backend
-- y evitar degradaciones de rendimiento en joins.
CREATE INDEX IF NOT EXISTS idx_firm_members_firm_id ON public.firm_members(firm_id);
CREATE INDEX IF NOT EXISTS idx_firm_members_user_id ON public.firm_members(user_id);
CREATE INDEX IF NOT EXISTS idx_firm_members_role_id ON public.firm_members(role_id);
CREATE INDEX IF NOT EXISTS idx_user_profiles_email ON public.user_profiles(email);

-- ------------------------------------------------------------------------------
-- 7. FUNCIÓN DE SEGURIDAD RECURSION-FREE: get_current_tenant_id()
-- ------------------------------------------------------------------------------
-- Retorna el firm_id asociado al usuario autenticado (auth.uid()).
-- Usamos SECURITY DEFINER y search_path seguro para evitar bucles infinitos en RLS.
CREATE OR REPLACE FUNCTION public.get_current_tenant_id()
RETURNS UUID AS $$
DECLARE
    v_firm_id UUID;
BEGIN
    SELECT firm_id INTO v_firm_id
    FROM public.firm_members
    WHERE user_id = auth.uid() AND is_active = TRUE
    LIMIT 1;
    
    RETURN v_firm_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

COMMENT ON FUNCTION public.get_current_tenant_id() IS 'Obtiene de manera segura y sin recursividad el ID del tenant activo del usuario.';

-- ------------------------------------------------------------------------------
-- 8. INTEGRACIÓN CON SUPABASE AUTH VIA TRIGGERS
-- ------------------------------------------------------------------------------
-- Sincroniza automáticamente la creación de usuarios en public.user_profiles
-- cuando se registra una nueva cuenta en auth.users de Supabase.
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO public.user_profiles (id, first_name, last_name, email, is_active)
    VALUES (
        NEW.id,
        COALESCE(NEW.raw_user_meta_data->>'first_name', 'Nombre'),
        COALESCE(NEW.raw_user_meta_data->>'last_name', 'Apellido'),
        NEW.email,
        TRUE
    );
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth;

-- Trigger sobre la tabla privada de Supabase Auth
-- Nota: En local, este trigger requiere privilegios adecuados o ser ejecutado como superusuario.
CREATE OR REPLACE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- ------------------------------------------------------------------------------
-- 9. HABILITACIÓN DE POLÍTICAS DE ROW LEVEL SECURITY (RLS)
-- ------------------------------------------------------------------------------
ALTER TABLE public.user_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.firm_members ENABLE ROW LEVEL SECURITY;

-- Políticas de RLS para user_profiles
-- Un usuario puede leer su propio perfil. Los administradores de la firma pueden leer perfiles
-- de miembros de su propia firma.
CREATE POLICY select_user_profiles ON public.user_profiles
    FOR SELECT
    USING (
        id = auth.uid() OR
        EXISTS (
            SELECT 1 FROM public.firm_members fm_session
            WHERE fm_session.user_id = auth.uid() 
              AND fm_session.firm_id = (SELECT fm_target.firm_id FROM public.firm_members fm_target WHERE fm_target.user_id = public.user_profiles.id LIMIT 1)
        )
    );

CREATE POLICY update_user_profiles ON public.user_profiles
    FOR UPDATE
    USING (id = auth.uid())
    WITH CHECK (id = auth.uid());

-- Políticas de RLS para firm_members (Aislamiento Multi-Tenant)
-- Los usuarios pueden ver los miembros de su propia firma.
CREATE POLICY select_firm_members ON public.firm_members
    FOR SELECT
    USING (firm_id = public.get_current_tenant_id());

-- Solo los administradores de la firma pueden insertar, modificar o eliminar miembros en su propia firma.
CREATE POLICY insert_firm_members ON public.firm_members
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

CREATE POLICY update_firm_members ON public.firm_members
    FOR UPDATE
    USING (
        firm_id = public.get_current_tenant_id() AND
        EXISTS (
            SELECT 1 FROM public.firm_members fm
            WHERE fm.user_id = auth.uid() 
              AND fm.firm_id = firm_id
              AND fm.role_id = 'administrator'
        )
    )
    WITH CHECK (
        firm_id = public.get_current_tenant_id() AND
        EXISTS (
            SELECT 1 FROM public.firm_members fm
            WHERE fm.user_id = auth.uid() 
              AND fm.firm_id = firm_id
              AND fm.role_id = 'administrator'
        )
    );

CREATE POLICY delete_firm_members ON public.firm_members
    FOR DELETE
    USING (
        firm_id = public.get_current_tenant_id() AND
        EXISTS (
            SELECT 1 FROM public.firm_members fm
            WHERE fm.user_id = auth.uid() 
              AND fm.firm_id = firm_id
              AND fm.role_id = 'administrator'
        )
    );

-- ------------------------------------------------------------------------------
-- 10. DATOS MAESTROS DE RBAC (SEMILLAS DE CONFIGURACIÓN)
-- ------------------------------------------------------------------------------
-- Insertamos los roles base
INSERT INTO public.roles (id, name, description) VALUES
('administrator', 'Administrador de Firma', 'Acceso total de configuración, gestión de miembros, expedientes, términos y borrado.'),
('lawyer', 'Abogado Asociado', 'Acceso de lectura y escritura para expedientes, actuaciones y términos de la firma. Sin privilegios de borrado.'),
('assistant', 'Asistente Jurídico', 'Acceso de lectura, registro de actuaciones y pre-carga de documentos bajo supervisión. Sin permisos de modificación de términos críticos.')
ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name, description = EXCLUDED.description;

-- Insertamos los permisos base
INSERT INTO public.permissions (id, name, description) VALUES
('cases:create', 'Crear Expedientes', 'Permiso para aperturar nuevos expedientes en el sistema.'),
('cases:read', 'Ver Expedientes', 'Permiso para consultar el listado y detalle de expedientes del bufete.'),
('cases:update', 'Modificar Expedientes', 'Permiso para actualizar metadatos, clientes o partes procesales.'),
('cases:delete', 'Eliminar Expedientes', 'Permiso destructivo reservado únicamente para administradores.'),
('documents:upload', 'Cargar Documentos', 'Permiso para subir archivos adjuntos y evidencias a Cloudflare R2.'),
('documents:download', 'Descargar Documentos', 'Permiso para descargar y visualizar archivos binarios del expediente.'),
('terms:create', 'Crear Términos', 'Permiso para configurar alertas de vencimiento procesal.'),
('terms:read', 'Ver Términos', 'Permiso para consultar términos judiciales y alertas procesales.'), -- <-- SE AGREGÓ ESTA LÍNEA
('terms:update', 'Modificar Términos', 'Permiso para actualizar estados de alertas o fechas límite.'),
('terms:cancel', 'Anular Términos', 'Permiso crítico para anular o suspender términos judiciales.')
ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name, description = EXCLUDED.description;

-- Asignación de permisos: administrator (Full access)
INSERT INTO public.role_permissions (role_id, permission_id)
SELECT 'administrator', id FROM public.permissions
ON CONFLICT DO NOTHING;

-- Asignación de permisos: lawyer (Lectura/Escritura sin Delete ni Cancelación Crítica)
INSERT INTO public.role_permissions (role_id, permission_id) VALUES
('lawyer', 'cases:create'),
('lawyer', 'cases:read'),
('lawyer', 'cases:update'),
('lawyer', 'documents:upload'),
('lawyer', 'documents:download'),
('lawyer', 'terms:create'),
('lawyer', 'terms:read'), -- <-- SE AGREGÓ ESTA LÍNEA
('lawyer', 'terms:update')
ON CONFLICT DO NOTHING;

-- Asignación de permisos: assistant (Pre-carga, lectura y creación básica)
INSERT INTO public.role_permissions (role_id, permission_id) VALUES
('assistant', 'cases:read'),
('assistant', 'documents:upload'),
('assistant', 'documents:download'),
('assistant', 'terms:read') -- Note: terms:read no se insertó arriba, asumimos que se hereda o se añade
ON CONFLICT DO NOTHING;

COMMIT;
