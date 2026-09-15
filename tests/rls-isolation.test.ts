/**
 * tests/rls-isolation.test.ts
 * Suite de Pruebas Adversariales de Aislamiento Multi-Tenant y RLS para LegalOS AI
 * 
 * Diseñado bajo principios SOLID, DRY y KISS para validación de seguridad Confianza Cero (Zero-Trust).
 * Ejecutado localmente y en el pipeline de CI/CD (GitHub Actions) mediante `npm run test:rls`.
 */

import { Client } from 'pg';
import dotenv from 'dotenv';
dotenv.config({ path: '.env.test' });

// Tipado estricto para contextualización de sesiones en pruebas
interface TestUserSession {
  userId: string;
  firmId: string;
  role: 'authenticated' | 'anon';
}

// Configuración de la conexión a PostgreSQL efímero de CI / local Supabase
const DATABASE_URL = process.env.DATABASE_URL || 'postgresql://postgres:postgres@localhost:54322/postgres';

describe('Suite Adversarial de Aislamiento Multi-Tenant (RLS & RBAC)', () => {
  let client: Client;

  // UUIDs estáticos para determinismo en la suite de pruebas
  const FIRM_A_ID = '11111111-1111-4111-a111-111111111111';
  const FIRM_B_ID = '22222222-2222-4222-a222-222222222222';

  const USER_A_LAWYER_ID = 'aaaa1111-1111-4111-a111-111111111111';
  const USER_A_ADMIN_ID  = 'aaaa2222-2222-4222-a222-222222222222';
  const USER_B_ADMIN_ID  = 'bbbb1111-1111-4111-a111-111111111111';

  const CASE_A_ID = 'caca1111-1111-4111-a111-111111111111';
  const CASE_B_ID = 'cbcb2222-2222-4222-a222-222222222222';

  /**
   * Helper DRY para impersonar el contexto de sesión de Supabase Auth en PostgreSQL.
   * Configura las variables de sesión locales (SET LOCAL) para simular el JWT claim.
   */
  async function applySessionContext(session: TestUserSession): Promise<void> {
    const jwtClaims = JSON.stringify({
      sub: session.userId,
      role: session.role,
      user_metadata: { firm_id: session.firmId },
      app_metadata: { provider: 'email' },
    });

    // Inyectar rol autenticado y claims JWT en el scope de la transacción SQL local
    await client.query(`SET LOCAL role = '${session.role}';`);
    await client.query(`SET LOCAL "request.jwt.claims" = '${jwtClaims}';`);
    await client.query(`SET LOCAL "request.jwt.claim.sub" = '${session.userId}';`);
  }

  beforeAll(async () => {
    client = new Client({ connectionString: DATABASE_URL });
    await client.connect();

    // Reset de prueba y sembrado superusuario (bypass RLS con superuser para fixtures base)
    await client.query('BEGIN;');

    // Limpieza previa idempotente
    await client.query(`
      DELETE FROM public.cases WHERE id IN ('${CASE_A_ID}', '${CASE_B_ID}');
      DELETE FROM public.firm_members WHERE user_id IN ('${USER_A_LAWYER_ID}', '${USER_A_ADMIN_ID}', '${USER_B_ADMIN_ID}');
      DELETE FROM public.user_profiles WHERE id IN ('${USER_A_LAWYER_ID}', '${USER_A_ADMIN_ID}', '${USER_B_ADMIN_ID}');
      DELETE FROM public.firms WHERE id IN ('${FIRM_A_ID}', '${FIRM_B_ID}');
      
      -- 1. Insertar firmas con formato de NIT válido (regex: '^[0-9]+-[0-9]$')
      INSERT INTO public.firms (id, name, nit) VALUES 
        ('${FIRM_A_ID}', 'Bufete Alfa Legal', '900111222-1'),
        ('${FIRM_B_ID}', 'Bufete Beta Asesores', '900333444-2');

      -- 2. Insertar perfiles de usuario
      INSERT INTO public.user_profiles (id, first_name, last_name, email) VALUES
        ('${USER_A_LAWYER_ID}', 'Abogado', 'Alfa', 'abogado.alfa@test.com'),
        ('${USER_A_ADMIN_ID}', 'Admin', 'Alfa', 'admin.alfa@test.com'),
        ('${USER_B_ADMIN_ID}', 'Admin', 'Beta', 'admin.beta@test.com');

      -- 3. Asignar membresías en firmas con roles correspondientes
      INSERT INTO public.firm_members (user_id, firm_id, role_id) VALUES 
        ('${USER_A_LAWYER_ID}', '${FIRM_A_ID}', 'lawyer'),
        ('${USER_A_ADMIN_ID}',  '${FIRM_A_ID}', 'administrator'),
        ('${USER_B_ADMIN_ID}',  '${FIRM_B_ID}', 'administrator');

      -- 4. Insertar expedientes base (cases)
      INSERT INTO public.cases (id, firm_id, title, case_number) VALUES 
        ('${CASE_A_ID}', '${FIRM_A_ID}', 'Proceso Alfa vs Estado', '11001400300120260000100'),
        ('${CASE_B_ID}', '${FIRM_B_ID}', 'Proceso Beta vs Particular', '11001400300120260000200');
    `);

    await client.query('COMMIT;');
  });

  afterAll(async () => {
    if (client) {
      try {
        await client.query('BEGIN;');
        await client.query(`
          DELETE FROM public.cases WHERE id IN ('${CASE_A_ID}', '${CASE_B_ID}');
          DELETE FROM public.firm_members WHERE user_id IN ('${USER_A_LAWYER_ID}', '${USER_A_ADMIN_ID}', '${USER_B_ADMIN_ID}');
          DELETE FROM public.user_profiles WHERE id IN ('${USER_A_LAWYER_ID}', '${USER_A_ADMIN_ID}', '${USER_B_ADMIN_ID}');
          DELETE FROM public.firms WHERE id IN ('${FIRM_A_ID}', '${FIRM_B_ID}');
        `);
        await client.query('COMMIT;');
      } catch (err) {
        console.error('Error during cleanup in afterAll:', err);
      } finally {
        await client.end();
      }
    }
  });

  beforeEach(async () => {
    // Iniciar transacción hermética para que cada caso se auto-limpie sin colaterales
    if (client) await client.query('BEGIN;');
  });

  afterEach(async () => {
    // Abortar la transacción para garantizar inmutabilidad entre pruebas
    if (client) await client.query('ROLLBACK;');
  });

  /**
   * Escenario A: Lectura Cruzada (Cross-Tenant SELECT / IDOR)
   * Ataque: Usuario de Firma A consulta expedientes sin filtro WHERE.
   * Expectativa: RLS debe filtrar transparentemente y devolver SOLO expedientes de Firma A.
   */
  it('Escenario A: Debe impedir la lectura cruzada de expedientes entre firmas (SELECT Aislamiento)', async () => {
    await applySessionContext({
      userId: USER_A_LAWYER_ID,
      firmId: FIRM_A_ID,
      role: 'authenticated',
    });

    const res = await client.query('SELECT id, title, firm_id FROM public.cases;');

    // Verificación 1: Todos los registros retornados deben pertenecer únicamente a Firma A
    expect(res.rows.length).toBeGreaterThan(0);
    const hasFirmBData = res.rows.some((row) => row.firm_id === FIRM_B_ID || row.id === CASE_B_ID);
    expect(hasFirmBData).toBe(false);

    // Verificación 2: El expediente de Firma A debe ser visible
    const hasFirmAData = res.rows.some((row) => row.id === CASE_A_ID);
    expect(hasFirmAData).toBe(true);
  });

  /**
   * Escenario B: Inyección en Escritura (Cross-Tenant INSERT)
   * Ataque: Usuario de Firma A intenta insertar un expediente asignando explícitamente `firm_id` de Firma B.
   * Expectativa: RLS WITH CHECK rechaza la transacción lanzando excepción de seguridad PostgreSQL.
   */
  it('Escenario B: Debe abortar transaccionalmente cualquier intento de inyección de tenant en INSERT', async () => {
    await applySessionContext({
      userId: USER_A_LAWYER_ID,
      firmId: FIRM_A_ID,
      role: 'authenticated',
    });

    const MALICIOUS_CASE_ID = '99999999-9999-4999-a999-999999999999';

    // Intento de inyección de tenant
    const insertPromise = client.query(`
      INSERT INTO public.cases (id, firm_id, title, case_number)
      VALUES ('${MALICIOUS_CASE_ID}', '${FIRM_B_ID}', 'Expediente Inyectado Ilegal', '11001400300120269999900');
    `);

    // Debe ser rechazado por la directiva WITH CHECK de RLS
    await expect(insertPromise).rejects.toThrow();
  });

  /**
   * Escenario C: Control de Acceso Basado en Roles (RBAC en DELETE Intra-Tenant)
   * Ataque: Abogado (rol 'lawyer') de Firma A intenta eliminar un expediente legítimo de su misma firma.
   * Expectativa: RLS RBAC impide el borrado (0 filas afectadas), mientras que el Administrador sí puede.
   */
  it('Escenario C: Debe restringir el borrado destructivo a nivel de rol (Abogado rechaza, Admin autoriza)', async () => {
    // 1. Intento por usuario con rol 'lawyer'
    await applySessionContext({
      userId: USER_A_LAWYER_ID,
      firmId: FIRM_A_ID,
      role: 'authenticated',
    });

    const lawyerDeleteRes = await client.query(`DELETE FROM public.cases WHERE id = '${CASE_A_ID}';`);
    expect(lawyerDeleteRes.rowCount).toBe(0);

    // 2. Intento por usuario con rol 'administrator' de la misma firma
    await applySessionContext({
      userId: USER_A_ADMIN_ID,
      firmId: FIRM_A_ID,
      role: 'authenticated',
    });

    const adminDeleteRes = await client.query(`DELETE FROM public.cases WHERE id = '${CASE_A_ID}';`);
    expect(adminDeleteRes.rowCount).toBe(1);
  });

  /**
   * Escenario D: Borrado Cruzado Inter-Tenant (Cross-Tenant DELETE)
   * Ataque: Administrador de Firma A intenta eliminar por ID un expediente perteneciente a Firma B.
   * Expectativa: RLS hace "invisible" el registro de Firma B, resultando en 0 filas afectadas.
   */
  it('Escenario D: Debe garantizar 0 filas afectadas en intentos de borrado inter-tenant por Administrador', async () => {
    await applySessionContext({
      userId: USER_A_ADMIN_ID,
      firmId: FIRM_A_ID,
      role: 'authenticated',
    });

    const crossDeleteRes = await client.query(`DELETE FROM public.cases WHERE id = '${CASE_B_ID}';`);

    // Para la sesión de Firma A, el registro de Firma B no existe en el espacio de tuplas
    expect(crossDeleteRes.rowCount).toBe(0);
  });
});
