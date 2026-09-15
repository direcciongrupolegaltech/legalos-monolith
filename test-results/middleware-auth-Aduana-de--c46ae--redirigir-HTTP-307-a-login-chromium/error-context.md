# Instructions

- Following Playwright test failed.
- Explain why, be concise, respect Playwright best practices.
- Provide a snippet of code with the fix, if possible.

# Test info

- Name: middleware-auth.spec.ts >> Aduana de Seguridad: Next.js Middleware Auth Guard >> Debe interceptar acceso no autenticado a /dashboard y redirigir HTTP 307 a /login
- Location: tests\e2e\middleware-auth.spec.ts:6:9

# Error details

```
Error: expect(received).toContain(expected) // indexOf

Expected value: 404
Received array: [307, 302, 200]
```

# Page snapshot

```yaml
- generic [ref=e3]:
  - heading "404" [level=1] [ref=e4]
  - heading "This page could not be found." [level=2] [ref=e6]
```

# Test source

```ts
  1  | import { test, expect } from '@playwright/test';
  2  | test.describe('Aduana de Seguridad: Next.js Middleware Auth Guard', () => { 
  3  |     // Garantizar estado anónimo puro en cada test (sin cookies de sesión previas) 
  4  |     test.use({ storageState: { cookies: [], origins: [] } }); 
  5  |     
  6  |     test('Debe interceptar acceso no autenticado a /dashboard y redirigir HTTP 307 a /login', async ({ page, baseURL }) => { 
  7  |         // 1\. Intentar navegar directamente a la ruta protegida 
  8  |         const response = await page.goto('/dashboard', { waitUntil: 'commit' }); 
  9  |         
  10 |         // 2\. Validar que la respuesta HTTP inicial sea de redirección 
  11 |         expect(response).not.toBeNull(); 
  12 |         const status = response?.status(); 
> 13 |         expect([307, 302, 200]).toContain(status); 
     |                                 ^ Error: expect(received).toContain(expected) // indexOf
  14 |         
  15 |         // 3\. Confirmar que la URL final contenga el parámetro de redirección 
  16 |         const currentUrl = page.url(); 
  17 |         expect(currentUrl).toBe(`${baseURL}/login?redirect=%2Fdashboard`); 
  18 |         
  19 |         // 4\. Validar que la interfaz renderizada corresponda al formulario de login 
  20 |         await expect(page.locator('input[type="email"], input[name="email"]')).toBeVisible({ timeout: 5000 }); }); 
  21 |         
  22 |         test('Debe retornar cabecera Location /login al consultar API /cases sin token JWT', async ({ request }) => { 
  23 |             // Evaluación rápida a nivel de red (API Request) sin renderizar DOM 
  24 |             const response = await request.get('/cases', { maxRedirects: 0 }); 
  25 |             
  26 |             expect(response.status()).toBe(307); 
  27 |             expect(response.headers()['location']).toBe('/login?redirect=%2Fcases'); 
  28 |         }); 
  29 |     });
```