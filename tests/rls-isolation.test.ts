import { Client } from 'pg';

/**
 * =============================================================================
 * SUITE DE PRUEBAS ADVERSARIALES DE AISLAMIENTO MULTI-TENANT (RLS) - LEGALOS
 * =============================================================================
 * Patrón de Arquitectura: Confianza Cero (Zero-Trust) & Shift-Left Testing
 * Diseñado por: Desarrollador de Software Senior / Arquitecto de Soluciones
 * Propósito: Simular ataques de inyección, IDOR, manipulación de payloads y
 *            violación de roles (RBAC) a nivel de motor de base de datos,
 *            certificando que las políticas de Row Level Security (RLS) de
 *            PostgreSQL son infranqueables ante fallos de la lógica del cliente.
 * 
 * Estrategia de Prueba: 
 * 1. Transacciones Herméticas: Cada test se ejecuta dentro de un bloque
 *    BEGIN...ROLLBACK para garantizar idempotencia total y cero mutaciones.
 * 2. Impersonación Directa: Inyección de claims JWT en el contexto local
 *    de PostgreSQL para suplantar identidades de Supabase Auth sin red externa.
 * =============================================================================
 */

const connectionString = process.env.DATABASE_URL || 'postgresql://postgres:postgres_secure_test_123@localhost:5432/legalos_test';

describe('Suite de Seguridad RLS: Pruebas Adversariales Multi-Tenant', () => {
  let db: Client;

  // --- SEMILLAS Y CONFIGURACIÓN DE IDENTIDADES DE PRUEBA CONTROLADAS ---
  const TENANT_A_FIRMA = 'a0000000-0000-0000-0000-00000000000a';
  const TENANT_B_FIRMA = 'b0000000-0000-0000-0000-00000000000b';

  // Firma A: Usuarios
  const USER_ADMIN_A = 'aaaa1111-1111-1111-1111-111111111111';
  const USER_ABOGADO_A = 'aaaa2222-2222-2222-2222-222222222222';

  // Firma B: Usuarios
  const USER_ADMIN_B = 'bbbb1111-1111-1111-1111-111111111111';

  // IDs de Expedientes Base
  const EXPEDIENTE_A_ID = 'e0000000-0000-0000-0000-00000000000a';
  const EXPEDIENTE_B_ID = 'e0000000-0000-0000-0000-00000000000b';

  beforeAll(async () => {
    db = new Client({ connectionString });
    await db.connect();

    // Aprovisionamiento preventivo de tablas de soporte organizacional para la simulación
    // Se asume el esquema físico definido en la especificación de RLS de LegalOS
    await db.query('BEGIN;');
    try {
      // 1. Limpieza estructural de entorno de pruebas
      await db.query('TRUNCATE TABLE audit_events, expedientes, members, firms CASCADE;');

      // 2. Insertar firmas (Tenants)
      await db.query(`
        INSERT INTO firms (id, name) VALUES 
        ('${TENANT_A_FIRMA}', 'Firma Corporativa Legal A'),
        ('${TENANT_B_FIRMA}', 'Bufete Asociados B');
      `);

      // 3. Registrar membresías y roles (RBAC)
      await db.query(`
        INSERT INTO members (user_id, firm_id, role) VALUES 
        ('${USER_ADMIN_A}', '${TENANT_A_FIRMA}', 'administrator'),
        ('${USER_ABOGADO_A}', '${TENANT_A_FIRMA}', 'lawyer'),
        ('${USER_ADMIN_B}', '${TENANT_B_FIRMA}', 'administrator');
      `);

      // 4. Registrar expedientes de prueba
      await db.query(`
        INSERT INTO expedientes (id, title, firm_id) VALUES 
        ('${EXPEDIENTE_A_ID}', 'Litigio Civil - Confidencial Firma A', '${TENANT_A_FIRMA}'),
        ('${EXPEDIENTE_B_ID}', 'Acción Penal de Fraude - Privado Firma B', '${TENANT_B_FIRMA}');
      `);

      await db.query('COMMIT;');
    } catch (error) {
      await db.query('ROLLBACK;');
      console.error('Fallo en la carga de semillas de seguridad para RLS test', error);
      throw error;
    }
  });

  afterAll(async () => {
    await db.end();
  });

  /**
   * Helper Técnico: Configura las variables locales de la sesión PostgreSQL
   * para emular de forma exacta las llamadas interceptadas de Supabase Auth
   * sin dependencias de red.
   */
  const setAuthContext = async (userId: string) => {
    const claims = JSON.stringify({
      sub: userId,
      role: 'authenticated',
      email: `${userId}@legalos.co`
    });
    await db.query(`SET LOCAL "request.jwt.claims" = '${claims}';`);
  };

  /**
   * ===========================================================================
   * ESCENARIO 1: ATAQUE DE LECTURA CRUZADA (SELECT IDOR VULNERABILITY)
   * ===========================================================================
   */
  test('ATAQUE DE LECTURA: Un abogado de la Firma A NO debe poder ver expedientes de la Firma B', async () => {
    await db.query('BEGIN;');
    try {
      // 1. Nos autenticamos como Abogado de la Firma A
      await setAuthContext(USER_ABOGADO_A);

      // 2. Ejecutamos una consulta SELECT general sobre expedientes sin filtros WHERE
      const result = await db.query('SELECT * FROM expedientes;');

      // 3. Verificaciones de seguridad (Assertions)
      // - El abogado de la Firma A debe ver su propio caso.
      const belongsToA = result.rows.some((r: { id: string }) => r.id === EXPEDIENTE_A_ID);
      expect(belongsToA).toBe(true);

      // - El expediente confidencial de la Firma B debe ser TOTALMENTE invisible.
      const leakFromB = result.rows.some((r: { id: string }) => r.id === EXPEDIENTE_B_ID);
      expect(leakFromB).toBe(false);
      
      // - El número total de filas devueltas debe restringirse en segundo plano
      expect(result.rows.length).toBe(1);

    } finally {
      await db.query('ROLLBACK;');
    }
  });

  /**
   * ===========================================================================
   * ESCENARIO 2: ATAQUE DE INYECCIÓN DE DATOS EN ESCRITURA (INSERT HIJACKING)
   * ===========================================================================
   */
  test('ATAQUE DE ESCRITURA: Usuario de la Firma A intenta inyectar un expediente forzando el ID de la Firma B', async () => {
    await db.query('BEGIN;');
    try {
      // 1. Nos autenticamos como el Abogado de la Firma A
      await setAuthContext(USER_ABOGADO_A);

      // 2. Intentamos realizar una inserción fraudulenta forzando la pertenencia a Firma B
      const maliciousPayload = {
        id: 'e9999999-9999-9999-9999-999999999999',
        title: 'Expediente Malicioso Inyectado desde Firma A',
        firm_id: TENANT_B_FIRMA // <--- Ataque: Intentando escribir en el espacio de Firma B
      };

      // 3. Ejecución y captura del error esperado de violación de política (WITH CHECK)
      let rlsBlocked = false;
      try {
        await db.query(`
          INSERT INTO expedientes (id, title, firm_id) 
          VALUES ('${maliciousPayload.id}', '${maliciousPayload.title}', '${maliciousPayload.firm_id}');
        `);
      } catch (error: any) {
        // PostgreSQL arroja el código de error 42501 para violaciones de políticas RLS (Insufficient Privilege)
        if (error.code === '42501') {
          rlsBlocked = true;
        } else {
          throw error;
        }
      }

      // 4. Certificación del bloqueo de infraestructura
      expect(rlsBlocked).toBe(true);

    } finally {
      await db.query('ROLLBACK;');
    }
  });

  /**
   * ===========================================================================
   * ESCENARIO 3: ATAQUE DE ACTUALIZACIÓN TRANSVERSAL (CROSS-TENANT UPDATE)
   * ===========================================================================
   */
  test('ATAQUE DE EDICIÓN: Un usuario de la Firma A intenta actualizar el expediente privado de la Firma B', async () => {
    await db.query('BEGIN;');
    try {
      // 1. Autenticar como Admin de la Firma A
      await setAuthContext(USER_ADMIN_A);

      // 2. Intentar actualizar el título del expediente de la Firma B
      const updateResult = await db.query(`
        UPDATE expedientes 
        SET title = 'TÍTULO SECUESTRADO POR ATACANTE DE FIRMA A' 
        WHERE id = '${EXPEDIENTE_B_ID}';
      `);

      // 3. Verificación de Afectación de Registros
      // Como el expediente de la Firma B es invisible para el usuario de la Firma A,
      // la cláusula WHERE no empareja nada, por lo que afecta a 0 filas.
      expect(updateResult.rowCount).toBe(0);

      // 4. Verificación de Consistencia Física (No alteración)
      // Cambiamos de contexto a la Firma B para comprobar que su dato sigue intacto
      await setAuthContext(USER_ADMIN_B);
      const verifyResult = await db.query(`SELECT title FROM expedientes WHERE id = '${EXPEDIENTE_B_ID}';`);
      expect(verifyResult.rows[0]?.title).toBe('Acción Penal de Fraude - Privado Firma B');

    } finally {
      await db.query('ROLLBACK;');
    }
  });

  /**
   * ===========================================================================
   * ESCENARIO 4: SEGURIDAD OPERATIVA Y RBAC (DELETE VETO LÓGICO)
   * ===========================================================================
   */
  test('SEGURIDAD RBAC: Un ABOGADO de la Firma A tiene vetado borrar expedientes de su propio bufete', async () => {
    await db.query('BEGIN;');
    try {
      // 1. Autenticar como el Abogado de la Firma A (Rol restrictivo: lawyer)
      await setAuthContext(USER_ABOGADO_A);

      // 2. El abogado intenta borrar el expediente de su propio bufete
      const deleteAttempt = await db.query(`DELETE FROM expedientes WHERE id = '${EXPEDIENTE_A_ID}';`);

      // 3. Verificación: RLS debe filtrar la acción de borrado basándose en el rol del miembro,
      // reportando que 0 filas fueron alteradas/borradas.
      expect(deleteAttempt.rowCount).toBe(0);

    } finally {
      await db.query('ROLLBACK;');
    }
  });

  /**
   * ===========================================================================
   * ESCENARIO 5: ELIMINACIÓN CRUZADA DE TENANTS (CROSS-TENANT DELETE ATTACK)
   * ===========================================================================
   */
  test('ATAQUE DE ELIMINACIÓN: El administrador de la Firma A intenta borrar el expediente de la Firma B', async () => {
    await db.query('BEGIN;');
    try {
      // 1. Autenticar como Administrador de la Firma A (Rol con privilegios de borrado en su propio tenant)
      await setAuthContext(USER_ADMIN_A);

      // 2. El Administrador intenta borrar el expediente de la Firma B
      const crossDeleteAttempt = await db.query(`DELETE FROM expedientes WHERE id = '${EXPEDIENTE_B_ID}';`);

      // 3. Verificación de Seguridad:
      // Para el Administrador de la Firma A, el expediente de la Firma B no existe debido a RLS,
      // por lo tanto la operación debe afectar exactamente a 0 filas.
      expect(crossDeleteAttempt.rowCount).toBe(0);

      // 4. Cambiar el contexto a Firma B para certificar que el expediente NO fue eliminado
      await setAuthContext(USER_ADMIN_B);
      const verifyPersistence = await db.query(`SELECT COUNT(*) FROM expedientes WHERE id = '${EXPEDIENTE_B_ID}';`);
      expect(parseInt(verifyPersistence.rows[0].count, 10)).toBe(1);

    } finally {
      await db.query('ROLLBACK;');
    }
  });

  /**
   * ===========================================================================
   * ESCENARIO 6: VERIFICACIÓN DEL GRUPO DE CONTROL (BYPASS DE RLS CON SERVICE_ROLE)
   * ===========================================================================
   */
  test('GRUPO DE CONTROL: Las APIs del sistema que operan bajo "service_role" deben poder ver todos los registros', async () => {
    await db.query('BEGIN;');
    try {
      // 1. Simulamos el rol del sistema o API del servidor (bypass de RLS de Supabase)
      // Esto simula las operaciones internas administrativas de LegalOS (ej. consolidación nocturna de términos)
      const claims = JSON.stringify({
        role: 'service_role' // <--- Bypass legítimo de seguridad de base de datos
      });
      await db.query(`SET LOCAL "request.jwt.claims" = '${claims}';`);

      // 2. Seleccionamos todos los expedientes
      const result = await db.query('SELECT * FROM expedientes;');

      // 3. Comprobamos que bajo el bypass administrativo se exponen ambos tenants sin barreras
      expect(result.rows.length).toBe(2);
      expect(result.rows.some((r: { id: string }) => r.id === EXPEDIENTE_A_ID)).toBe(true);
      expect(result.rows.some((r: { id: string }) => r.id === EXPEDIENTE_B_ID)).toBe(true);

    } finally {
      await db.query('ROLLBACK;');
    }
  });
});
