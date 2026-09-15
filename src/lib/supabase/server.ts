import { createServerClient } from '@supabase/ssr';
import { cookies } from 'next/headers';

/**
 * Cliente de Supabase Auth para el Servidor (Server Components, Server Actions y API Routes)
 * Permite leer e inyectar cookies de sesión en las cabeceras HTTP de Next.js App Router.
 */
export async function createClient() {
  const cookieStore = await cookies();

  const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL!;
  const supabaseAnonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!;

  return createServerClient(supabaseUrl, supabaseAnonKey, {
    cookies: {
      getAll() {
        return cookieStore.getAll();
      },
      setAll(cookiesToSet) {
        try {
          cookiesToSet.forEach(({ name, value, options }) =>
            cookieStore.set(name, value, options)
          );
        } catch {
          // Invocado desde un Server Component puro; las cookies las gestiona el middleware.
        }
      },
    },
  });
}

/**
 * Helper de Dominio y Seguridad: Extracción de Contexto de Usuario e Inquilino (Tenant Context)
 * Retorna el usuario autenticado, el firm_id activo y su rol en la firma procesal.
 */
export async function getCurrentUserAndTenant() {
  const supabase = await createClient();

  const { data: { user }, error: authError } = await supabase.auth.getUser();

  if (authError || !user) {
    return { user: null, firmId: null, roleId: null, error: 'Sesión no válida o expirable' };
  }

  const { data: membership, error: memberError } = await supabase
    .from('firm_members')
    .select('firm_id, role_id, is_active')
    .eq('user_id', user.id)
    .eq('is_active', true)
    .single();

  if (memberError || !membership) {
    return {
      user,
      firmId: null,
      roleId: null,
      error: 'Usuario sin membresía activa en ninguna firma procesal',
    };
  }

  return {
    user,
    firmId: membership.firm_id as string,
    roleId: membership.role_id as string,
    error: null,
  };
}
