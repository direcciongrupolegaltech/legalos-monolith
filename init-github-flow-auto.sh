#!/usr/bin/env bash

# =============================================================================
# Script de Inicialización y Blindaje Automático - GitHub Flow (LegalOS) - V2
# =============================================================================
# Diseñado por: Desarrollador de Software Senior / Arquitecto de Soluciones
# Propósito: Configurar el entorno local, inyectar los scripts requeridos en
#            package.json, crear las configuraciones de ESLint y TypeScript
#            estricto (.eslintrc.json y tsconfig.json), configurar exclusiones,
#            y estructurar los ganchos de pre-commit y workflows (Zero-Trust).
# =============================================================================

set -euo pipefail

# --- CONFIGURACIÓN DE COLORES PARA SALIDA ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# --- VALIDACIONES DE ENTORNO PREVIAS (FAIL-FAST) ---

# 1. Validar que se esté ejecutando en la raíz de un proyecto Node.js
if [ ! -f "package.json" ]; then
    log_error "Este script debe ejecutarse en la raíz de un proyecto Node.js (Falta package.json)."
    exit 1
fi

# 2. Verificar dependencias del sistema indispensables
for cmd in git npm node; do
    if ! command -v "$cmd" &> /dev/null; then
        log_error "El ejecutable obligatorio '$cmd' no está instalado o no se encuentra en el PATH."
        exit 1
    fi
done

log_info "Iniciando configuración y blindaje de aduanas de calidad para LegalOS (v2)..."

# --- 1. INICIALIZACIÓN DE REPOSITORIO GIT ---
if [ ! -d ".git" ]; then
    log_info "Inicializando repositorio Git local..."
    git init
else
    log_warn "Ya existe un repositorio Git en este directorio."
fi

# Asegurar que la rama predeterminada sea 'main'
git branch -M main
log_success "Rama predeterminada configurada como: main"

# --- 2. CONFIGURACIÓN E INYECCIÓN DE SCRIPTS EN PACKAGE.JSON (AUTOMATIZADO) ---
log_info "Inyectando scripts de calidad (lint, typecheck, test:rls) en package.json..."

# Utilizamos un script inline de Node.js por ser nativo, robusto, portable y evitar dependencias de terceros como jq.
node -e '
const fs = require("fs");
const path = "package.json";
try {
  const pkg = JSON.parse(fs.readFileSync(path, "utf8"));
  pkg.scripts = pkg.scripts || {};
  
  let modified = false;

  if (pkg.scripts.lint !== "eslint src") {
    pkg.scripts.lint = "eslint src";
    modified = true;
  }
  if (pkg.scripts.typecheck !== "tsc --noEmit") {
    pkg.scripts.typecheck = "tsc --noEmit";
    modified = true;
  }
  if (pkg.scripts["test:rls"] !== "jest tests/rls-isolation.test.ts") {
    pkg.scripts["test:rls"] = "jest tests/rls-isolation.test.ts";
    modified = true;
  }

  if (modified) {
    fs.writeFileSync(path, JSON.stringify(pkg, null, 2) + "\n", "utf8");
    console.log("UPDATED");
  } else {
    console.log("NO_CHANGE");
  }
} catch (e) {
  console.error("ERROR", e.message);
  process.exit(1);
}
' > /tmp/node_pkg_status.txt

if [ "$(cat /tmp/node_pkg_status.txt)" = "UPDATED" ]; then
    log_success "package.json actualizado con éxito. Scripts inyectados: lint, typecheck, test:rls."
else
    log_info "package.json ya contiene los scripts de calidad requeridos."
fi
rm -f /tmp/node_pkg_status.txt

# --- 3. CREACIÓN DE ARCHIVOS DE CONFIGURACIÓN DE CALIDAD ---

# 3.1 ESLint (.eslintrc.json)
if [ ! -f ".eslintrc.json" ] && [ ! -f ".eslintrc.js" ]; then
    log_info "Creando archivo .eslintrc.json con estándares de seguridad..."
    cat << 'EOF' > .eslintrc.json
{
  "extends": [
    "next/core-web-vitals",
    "plugin:@typescript-eslint/recommended"
  ],
  "plugins": [
    "@typescript-eslint"
  ],
  "rules": {
    "no-unused-vars": "off",
    "@typescript-eslint/no-unused-vars": ["error", { "argsIgnorePattern": "^_" }],
    "@typescript-eslint/no-explicit-any": "error",
    "@typescript-eslint/no-floating-promises": "error",
    "@typescript-eslint/no-misused-promises": "error",
    "no-console": ["warn", { "allow": ["warn", "error"] }]
  }
}
EOF
    log_success "Archivo .eslintrc.json creado exitosamente."
else
    log_warn "Ya existe una configuración de ESLint en el directorio raíz. Se omitió la creación para evitar conflictos."
fi

# 3.2 TypeScript Estricto (tsconfig.json)
if [ ! -f "tsconfig.json" ]; then
    log_info "Creando archivo tsconfig.json con directivas estrictas de aislamiento..."
    cat << 'EOF' > tsconfig.json
{
  "compilerOptions": {
    "target": "ES2022",
    "lib": ["dom", "dom.iterable", "esnext"],
    "allowJs": true,
    "skipLibCheck": true,
    "strict": true,
    "forceConsistentCasingInFileNames": true,
    "noEmit": true,
    "esModuleInterop": true,
    "module": "esnext",
    "moduleResolution": "bundler",
    "resolveJsonModule": true,
    "isolatedModules": true,
    "jsx": "preserve",
    "incremental": true,
    "plugins": [
      {
        "name": "next"
      }
    ],
    "paths": {
      "@/*": ["./src/*"],
      "@/supabase/*": ["./supabase/*"],
      "@/tests/*": ["./tests/*"]
    },

    /* CONFIGURACIONES ESTRICTAS ADICIONALES PARA EL BLINDAJE DE LEGALOS */
    "noImplicitAny": true,
    "strictNullChecks": true,
    "strictFunctionTypes": true,
    "strictBindCallApply": true,
    "strictPropertyInitialization": true,
    "noImplicitThis": true,
    "alwaysStrict": true,

    /* Mitigación de errores lógicos y de ejecución en producción */
    "noUnusedLocals": true,
    "noUnusedParameters": true,
    "noImplicitReturns": true,
    "noFallthroughCasesInSwitch": true,

    /* 
      noUncheckedIndexedAccess: CRÍTICO PARA SUPABASE Y LLM RESPONSES.
      Fuerza a tratar cualquier acceso por índice dinámico o fila de BD 
      como potencialmente 'undefined', obligando a realizar comprobaciones 
      de nulidad antes de acceder a sus propiedades. Previene fallos de 
      "Cannot read property of undefined" en producción.
    */
    "noUncheckedIndexedAccess": true,

    /* 
      exactOptionalPropertyTypes: Garantiza la correspondencia con PostgreSQL.
      Evita que propiedades marcadas como opcionales (?) sean asignadas como 
      'undefined'. En base de datos, una propiedad ausente es distinta a una 
      columna con valor explícito nulo o indefinido.
    */
    "exactOptionalPropertyTypes": true
  },
  "include": [
    "next-env.d.ts",
    "**/*.ts",
    "**/*.tsx",
    ".next/types/**/*.ts",
    "src/lib/supabase-types.ts"
  ],
  "exclude": [
    "node_modules",
    "dist",
    ".next"
  ]
}
EOF
    log_success "Archivo tsconfig.json inyectado con directivas estrictas de seguridad de tipos."
else
    log_warn "Ya existe un archivo tsconfig.json en el directorio raíz. Se omitió la creación para preservar configuraciones existentes."
fi

# --- 4. CONFIGURACIÓN DE EXCLUSIONES (.gitignore) ---
log_info "Generando y optimizando archivo .gitignore..."
cat << 'EOF' > .gitignore
# Next.js - Compilación y dependencias
node_modules/
.next/
out/
build/

# Entornos y secretos (DM-01: No exponer credenciales)
.env
.env.local
.env.development.local
.env.preview.local
.env.production.local
.env*.local

# Logs y diagnóstico
npm-debug.log*
yarn-debug.log*
yarn-error.log*
.pnpm-debug.log*
.eslintcache

# Supabase - Datos locales temporales y secretos
supabase/.temp/
supabase/pull/
.supabase/

# Cloudflare - Archivos de configuración local y wrangler
.wrangler/
dist/

# Archivos de sistema y editores
.DS_Store
Thumbs.db
.vscode/
.idea/
*.suo
*.ntvs*
*.njsproj
*.sln
*.swp
EOF
log_success "Archivo .gitignore configurado de forma hermética."

# --- 5. CREACIÓN DE ESTRUCTURA DE GOBERNANZA (.github) ---
log_info "Creando estructura de directorios para GitHub..."
mkdir -p .github/workflows
mkdir -p .git/hooks

# --- 5.1 Plantilla de Pull Request (Aduana Humana / DoD) ---
log_info "Configurando plantilla de Pull Request (.github/pull_request_template.md)..."
cat << 'EOF' > .github/pull_request_template.md
# 📑 PLANTILLA DE PULL REQUEST - LEGALOS AI

## 🎯 DESCRIPCIÓN DE LOS CAMBIOS
<!-- Describe de forma clara y concisa el propósito técnico de este cambio, el problema de negocio que resuelve y las implicaciones de arquitectura. -->

* **Tipo de cambio:** [ ] Nueva característica (`feat`) | [ ] Corrección de errores (`fix`) | [ ] Mantenimiento/Tooling (`chore`/`refactor`)
* **Módulo afectado:** [ ] Autenticación/Tenancy | [ ] Expedientes | [ ] Términos Judiciales | [ ] Almacenamiento R2 | [ ] Inteligencia Artificial | [ ] Financiero/Bandeja
* **ID de Tarea/Issue asociado:** #

---

## 🛡️ ADUANAS DE SEGURIDAD MULTI-TENANT & RLS
*De acuerdo con el Principio de Confianza Cero (DM-01, Sección 15.7), el aislamiento entre firmas es un pilar del dominio de datos y debe validarse de forma obligatoria antes de realizar la fusión de ramas.*

- [ ] **Verificación de Aislamiento (Anti-IDOR):** He verificado y certificado que todas las consultas y escrituras a la base de datos realizadas en este cambio están explícita o implícitamente filtradas por el identificador de inquilino `firm_id`.
- [ ] **Políticas RLS Activas:** Los cambios en el esquema de base de datos incluyen sus respectivas políticas de Row Level Security (RLS) habilitadas en PostgreSQL.
- [ ] **Suite de Pruebas Automatizadas:** He ejecutado localmente la suite adversarial `npm run test:rls` (basada en el archivo `rls-isolation.test.ts`) y todas las pruebas de intrusión cruzada han pasado de forma exitosa en verde.
- [ ] **No hay filtración de información cruzada:** Se garantiza de forma fehaciente que un usuario de la Firma A no puede acceder a expedientes, documentos o metadatos privados de la Firma B.

---

## 🗃️ CONTROL DE BASE DE DATOS Y MIGRACIONES
- [ ] **Versionado Secuencial:** Las migraciones SQL asociadas siguen la nomenclatura cronológica ordenada del CLI de Supabase dentro del directorio oficial `supabase/migrations/`.
- [ ] **Datos de Prueba (Seed):** Si se requieren catálogos o datos de soporte nacional, se han mapeado e integrado correctamente sin datos reales de clientes en `seed.sql`.

---

## 🧪 CHECKLIST DE CONTROL DE CALIDAD TÉCNICO (DoD)
*Gobernanza del código y criterios de finalización de desarrollo (Definition of Done).*

### Compilación y Calidad Estática:
- [ ] **Análisis Estático (Linter):** He ejecutado exitosamente `npm run lint` y el código está libre de errores de estilo o malas prácticas.
- [ ] **Tipado Estricto de TypeScript (Typecheck):** He verificado la cohesión lógica ejecutando `npm run typecheck` (`tsc --noEmit` sin advertencias ni tipos implícitos de variables sensibles).
- [ ] **Compilación de Producción (Next.js Build):** El monolito modular compila de forma exitosa localmente ejecutando `npm run build`.

### Funcionalidad e Interfaces:
- [ ] **Interfaz Adaptable (Responsive):** Si incluye frontend, el diseño se adapta de forma fluida a pantallas de portátiles y tablets.
- [ ] **Manejo de Estados:** La interfaz maneja de forma correcta y visual los estados de carga, vistas vacías, errores de negocio y denegación de permisos.
- [ ] **Auditoría inmutable:** Las operaciones críticas (como cambios de fechas límite de términos, cancelaciones de alertas o descargas de documentos) registran su correspondiente evento en `audit_events`.

---

## 👥 REVISIÓN HUMANA (REQUISITO REFORZADO)
- [ ] **Aprobación Técnica Obligatoria:** Este cambio requiere la aprobación de al menos un Desarrollador Senior o Arquitecto de Soluciones antes de su fusión.
- [ ] **Asistencia vs Revisión:** Se certifica que las herramientas de asistencia de IA (Cursor, Copilot, etc.) se usaron únicamente para codificación, mas no para actuar como revisores o autorizadores de la mezcla.
EOF
log_success "Plantilla de Pull Request inyectada correctamente."

# --- 5.2 Workflow de Integración Continua (ci-workflow.yml) ---
log_info "Configurando pipeline de Integración Continua (.github/workflows/ci-workflow.yml)..."
cat << 'EOF' > .github/workflows/ci-workflow.yml
name: LegalOS Integration CI

on:
  pull_request:
    branches: [ main ]

jobs:
  validate:
    runs-on: ubuntu-latest

    services:
      postgres:
        image: postgres:15-alpine
        env:
          POSTGRES_DB: legalos_test
          POSTGRES_PASSWORD: postgres_secure_test_123
        ports:
          - 5432:5432
        options: >-
          --health-cmd pg_isready
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5

    steps:
      - name: Checkout Código Fuente
        uses: actions/checkout@v3

      - name: Setup Node.js con Cache Optimizado
        uses: actions/setup-node@v3
        with:
          node-version: '20'
          cache: 'npm'

      - name: Instalar Dependencias
        run: npm ci

      - name: Ejecutar Linter Estático
        run: npm run lint

      - name: Ejecutar Compilador Estático TypeScript
        run: npm run typecheck

      - name: Validar Estructura y Políticas RLS en Base de Datos
        env:
          DATABASE_URL: postgresql://postgres:postgres_secure_test_123@localhost:5432/legalos_test
        run: |
          # 1. Aplicar migraciones ordenadas de Supabase CLI en el Postgres local
          # 2. Correr la suite adversarial rls-isolation.test.ts para bloquear fugas multi-tenant
          npm run test:rls

      - name: Compilar Monolito Next.js
        run: npm run build
EOF
log_success "Pipeline de Integración Continua (CI) inyectado correctamente."

# --- 5.3 Workflow de Entrega Continua (release-on-merge.yml) ---
log_info "Configurando pipeline de Entrega Continua (.github/workflows/release-on-merge.yml)..."
cat << 'EOF' > .github/workflows/release-on-merge.yml
name: Release on Merge

on:
  push:
    branches:
      - main

permissions:
  contents: write
  pull-requests: read

jobs:
  draft-release:
    name: Generate Release Tag & Draft Notes
    runs-on: ubuntu-latest
    steps:
      - name: Checkout Repository
        uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Read Version from package.json
        id: get_version
        run: |
          VERSION=$(node -p "require('./package.json').version")
          echo "VERSION=$VERSION" >> $GITHUB_OUTPUT
          echo "Detectada versión del proyecto: v$VERSION"

      - name: Verify Tag Existence
        id: check_tag
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          TAG_NAME="v${{ steps.get_version.outputs.VERSION }}"
          EXISTS=$(gh api repos/${{ github.repository }}/git/ref/tags/$TAG_NAME --silent > /dev/null && echo "true" || echo "false")
          echo "EXISTS=$EXISTS" >> $GITHUB_OUTPUT
          echo "El tag $TAG_NAME existe?: $EXISTS"

      - name: Create GitHub Release Draft
        if: steps.check_tag.outputs.EXISTS == 'false'
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          TAG_NAME="v${{ steps.get_version.outputs.VERSION }}"
          echo "Creando versión borrador para $TAG_NAME..."
          gh release create "$TAG_NAME" \
            --draft \
            --title "Release $TAG_NAME" \
            --generate-notes

      - name: Handle Duplicate Version (Warning)
        if: steps.check_tag.outputs.EXISTS == 'true'
        run: |
          echo "::warning title=Versión Duplicada::La versión v${{ steps.get_version.outputs.VERSION }} ya está etiquetada en GitHub. Incrementa el campo 'version' en package.json en tu rama de trabajo para generar un nuevo release al mezclar."
EOF
log_success "Pipeline de Entrega Continua (CD) inyectado correctamente."

# --- 6. INSTALACIÓN DE GANCHO PRE-COMMIT (Aduana Local) ---
log_info "Configurando Hook de Pre-Commit (.git/hooks/pre-commit)..."
hookPath=".git/hooks/pre-commit"

# Crear el hook asegurando que use la sintaxis Unix LF
cat << 'EOF' > "$hookPath"
#!/usr/bin/env bash
set -euo pipefail

# Colores para CLI
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}[Aduana Pre-Commit]${NC} Verificando calidad estática local..."

# A. Ejecución del Linter
echo -e "${BLUE}[Aduana]${NC} Ejecutando linter estático (npm run lint)..."
if ! npm run lint; then
    echo -e "${RED}[FALLO]${NC} El linter reportó errores. Corrígelos antes de realizar la confirmación."
    exit 1
fi

# B. Ejecución de la validación estricta de TypeScript
echo -e "${BLUE}[Aduana]${NC} Verificando tipado estricto (npm run typecheck)..."
if ! npm run typecheck; then
    echo -e "${RED}[FALLO]${NC} Errores en la validación estricta de tipos de TypeScript."
    exit 1
fi

echo -e "${GREEN}[Ok]${NC} El código cumple los estándares estáticos de calidad local. Registrando commit."
exit 0
EOF

# Otorgar permisos de ejecución de forma obligatoria
chmod +x "$hookPath"
log_success "Hook de pre-commit instalado y configurado como ejecutable."

# --- NOTA FINAL DE USO ---
echo -e "\n${GREEN}==============================================================${NC}"
echo -e "          ${GREEN}BLINDAJE DE SEGURIDAD LEGALOS COMPLETADO (V2)${NC}"
echo -e "${GREEN}==============================================================${NC}"
echo -e "Las aduanas locales y en la nube han sido instaladas con éxito."
echo -e "Se actualizaron package.json, .eslintrc.json y tsconfig.json."
echo -e "Recuerda añadir estos cambios al control de versiones ejecutando:"
echo -e "  ${YELLOW}git add .eslintrc.json tsconfig.json package.json .github/ .gitignore && git commit -m 'chore: aduanas de calidad robustas'${NC}"
echo -e "${GREEN}==============================================================${NC}\n"
