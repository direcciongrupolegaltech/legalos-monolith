import { createBrowserClient } from '@supabase/ssr';

let clientInstance: ReturnType<typeof createBrowserClient> | null = null;

/**
 * Cliente de Supabase Auth para el Navegador (React Client Components)
 * Implementa el patrón Singleton para reutilizar la conexión y evitar fugas de memoria.
 */
export function createClient() {
  const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const supabaseAnonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;

  if (!supabaseUrl || !supabaseAnonKey) {
    throw new Error(
      '[Supabase Client Error] Variables de entorno NEXT_PUBLIC_SUPABASE_URL y NEXT_PUBLIC_SUPABASE_ANON_KEY no configuradas.'
    );
  }

  if (typeof window === 'undefined') {
    return createBrowserClient(supabaseUrl, supabaseAnonKey);
  }

  if (!clientInstance) {
    clientInstance = createBrowserClient(supabaseUrl, supabaseAnonKey);
  }

  return clientInstance;
}
