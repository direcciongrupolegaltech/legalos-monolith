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
