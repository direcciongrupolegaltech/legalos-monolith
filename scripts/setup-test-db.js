/**
 * scripts/setup-test-db.js
 * Script de inicialización y ejecución de migraciones para la base de datos de pruebas (CI y local).
 * 
 * - Configura roles requeridos por Supabase (authenticated, anon).
 * - Inicializa el esquema 'auth', tabla 'auth.users' y función 'auth.uid()'.
 * - Aplica todas las migraciones en orden cronológico desde supabase/migrations/.
 */

const { Client } = require('pg');
const fs = require('fs');
const path = require('path');
const dotenv = require('dotenv');

dotenv.config({ path: '.env.test' });

const DATABASE_URL = process.env.DATABASE_URL || 'postgresql://postgres:postgres@localhost:54322/postgres';

async function setupTestDatabase() {
  console.log(`[DB SETUP] Conectando a PostgreSQL para inicialización de migraciones...`);
  const client = new Client({ connectionString: DATABASE_URL });

  try {
    await client.connect();
    console.log(`[DB SETUP] Conexión establecida.`);

    // 1. Asegurar roles necesarios para Supabase Auth y RLS
    console.log(`[DB SETUP] Asegurando roles de base de datos ('authenticated', 'anon')...`);
    await client.query(`
      DO $$
      BEGIN
        IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'authenticated') THEN
          CREATE ROLE authenticated NOLOGIN NOINHERIT;
        END IF;
        IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'anon') THEN
          CREATE ROLE anon NOLOGIN NOINHERIT;
        END IF;
      END
      $$;
    `);

    // 2. Asegurar esquema y funciones simuladas de Supabase Auth
    console.log(`[DB SETUP] Creando esquema 'auth' y funciones 'auth.uid()'...`);
    await client.query(`
      CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
      CREATE EXTENSION IF NOT EXISTS "pgcrypto";

      CREATE SCHEMA IF NOT EXISTS auth;

      CREATE TABLE IF NOT EXISTS auth.users (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        email TEXT UNIQUE,
        raw_user_meta_data JSONB DEFAULT '{}'::jsonb,
        created_at TIMESTAMPTZ DEFAULT now()
      );

      CREATE OR REPLACE FUNCTION auth.uid() RETURNS UUID AS $$
        SELECT NULLIF(current_setting('request.jwt.claim.sub', true), '')::uuid;
      $$ LANGUAGE sql STABLE;

      CREATE OR REPLACE FUNCTION auth.role() RETURNS TEXT AS $$
        SELECT NULLIF(current_setting('request.jwt.claim.role', true), '')::text;
      $$ LANGUAGE sql STABLE;

      GRANT USAGE ON SCHEMA public TO authenticated, anon;
      GRANT USAGE ON SCHEMA auth TO authenticated, anon;
      GRANT ALL ON ALL TABLES IN SCHEMA public TO postgres, authenticated;
      GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO postgres, authenticated;
      GRANT ALL ON ALL ROUTINES IN SCHEMA public TO postgres, authenticated;
      GRANT SELECT ON auth.users TO authenticated;
    `);

    // 3. Obtener y ordenar migraciones SQL
    const migrationsDir = path.join(__dirname, '..', 'supabase', 'migrations');
    if (!fs.existsSync(migrationsDir)) {
      throw new Error(`Directorio de migraciones no encontrado en: ${migrationsDir}`);
    }

    const migrationFiles = fs
      .readdirSync(migrationsDir)
      .filter((file) => file.endsWith('.sql'))
      .sort();

    console.log(`[DB SETUP] Se encontraron ${migrationFiles.length} migraciones.`);

    for (const file of migrationFiles) {
      const filePath = path.join(migrationsDir, file);
      const sql = fs.readFileSync(filePath, 'utf8');

      console.log(`[DB SETUP] Aplicando migración: ${file}...`);
      await client.query(sql);
      console.log(`[DB SETUP] -> Migración ${file} aplicada con éxito.`);
    }

    // Asegurar permisos sobre las tablas recién creadas para el rol authenticated
    await client.query(`
      GRANT ALL ON ALL TABLES IN SCHEMA public TO postgres, authenticated;
      GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO postgres, authenticated;
      GRANT ALL ON ALL ROUTINES IN SCHEMA public TO postgres, authenticated;
    `);

    console.log(`[DB SETUP] Base de datos de prueba configurada y migrada exitosamente.`);
  } catch (error) {
    console.error(`[DB SETUP ERROR] Fallo al inicializar la base de datos:`, error);
    process.exit(1);
  } finally {
    await client.end();
  }
}

setupTestDatabase();
