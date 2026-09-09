/**
 * feature-flags.ts
 * Administrador de características con seguridad de tipos para Next.js (LegalOS AI)
 * Diseñado bajo principios SOLID, DRY y KISS para entornos de confianza cero.
 */

// 1. Tipado estricto de llaves de características (FeatureKey) [51]
export type FeatureKey =
  | 'MODULE_OCR_IA'          // Procesamiento asíncrono OCR e IA
  | 'STORAGE_R2_PRIVATE'     // Almacenamiento seguro en Cloudflare R2
  | 'DAILY_INBOX_V2'         // Bandeja de entrada del día V2
  | 'FINANCIAL_LEDGER';      // Libro financiero y control de honorarios

// Definición de etapas de despliegue [51]
export type DeploymentStage = 'development' | 'staging' | 'production' | 'all';

// Interfaz de configuración de banderas
interface FeatureConfig {
  stage: DeploymentStage;
  description: string;
}

// 2. Registro interno de características por etapa [51]
const FEATURE_REGISTRY: Record<FeatureKey, FeatureConfig> = {
  MODULE_OCR_IA: {
    stage: 'development',
    description: 'Procesamiento de documentos y extracción OCR mediante IA',
  },
  STORAGE_R2_PRIVATE: {
    stage: 'staging',
    description: 'Integración y firmado de URLs para Cloudflare R2',
  },
  DAILY_INBOX_V2: {
    stage: 'staging',
    description: 'Bandeja operativa consolidada y priorizada para abogados',
  },
  FINANCIAL_LEDGER: {
    stage: 'production', // Habilitado en producción por defecto
    description: 'Módulo financiero base de acuerdos de pago e ingresos',
  },
};

/**
 * Determina el entorno de ejecución de Next.js
 */
function getCurrentEnvironment(): DeploymentStage {
  const env = process.env.NODE_ENV || 'development';
  if (process.env.NEXT_PUBLIC_APP_STAGE === 'staging') {
    return 'staging';
  }
  return env as DeploymentStage;
}

/**
 * Evalúa si una bandera de característica está activa.
 * Soporta inyección y overrides mediante variables de entorno. [52]
 */
export function isFeatureActive(key: FeatureKey): boolean {
  const config = FEATURE_REGISTRY[key];
  if (!config) return false;

  // A. Evaluación por Overrides de Variables de Entorno [52]
  const envVarName = `NEXT_PUBLIC_FEATURE_${key}`;
  const envOverride = process.env[envVarName];

  if (envOverride !== undefined) {
    return envOverride === 'true';
  }

  // B. Evaluación por Etapa de Despliegue [51]
  const currentEnv = getCurrentEnvironment();

  if (config.stage === 'all') {
    return true;
  }

  if (config.stage === 'development' && currentEnv === 'development') {
    return true;
  }

  if (config.stage === 'staging' && (currentEnv === 'development' || currentEnv === 'staging')) {
    return true;
  }

  if (config.stage === 'production') {
    // 'production' implica que está disponible en todas las etapas
    return true;
  }

  return false;
}

export interface DebugManifestItem {
  active: boolean;
  config: FeatureConfig;
}

export type DebugManifest = Record<FeatureKey, DebugManifestItem>;

/**
 * Retorna el manifiesto actual de características para depuración.
 * Defensa en Producción: Deshabilitado en producción para evitar ingeniería inversa. [52]
 */
export function getDebugManifest(): DebugManifest | null {
  const currentEnv = getCurrentEnvironment();

  if (currentEnv === 'production') {
    // Bloqueo estricto de exposición de metadatos en producción [52]
    return null;
  }

  const manifest = {} as DebugManifest;
  for (const key of Object.keys(FEATURE_REGISTRY) as FeatureKey[]) {
    manifest[key] = {
      active: isFeatureActive(key),
      config: FEATURE_REGISTRY[key],
    };
  }

  return manifest;
}
