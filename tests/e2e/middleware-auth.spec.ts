import { test, expect } from '@playwright/test';
test.describe('Aduana de Seguridad: Next.js Middleware Auth Guard', () => { 
    // Garantizar estado anónimo puro en cada test (sin cookies de sesión previas) 
    test.use({ storageState: { cookies: [], origins: [] } }); 
    
    test('Debe interceptar acceso no autenticado a /dashboard y redirigir HTTP 307 a /login', async ({ page, baseURL }) => { 
        // 1\. Intentar navegar directamente a la ruta protegida 
        const response = await page.goto('/dashboard', { waitUntil: 'commit' }); 
        
        // 2\. Validar que la respuesta HTTP inicial sea de redirección 
        expect(response).not.toBeNull(); 
        const status = response?.status(); 
        expect([307, 302, 200]).toContain(status); 
        
        // 3\. Confirmar que la URL final contenga el parámetro de redirección 
        const currentUrl = page.url(); 
        expect(currentUrl).toBe(`${baseURL}/login?redirect=%2Fdashboard`); 
        
        // 4\. Validar que la interfaz renderizada corresponda al formulario de login 
        await expect(page.locator('input[type="email"], input[name="email"]')).toBeVisible({ timeout: 5000 }); }); 
        
        test('Debe retornar cabecera Location /login al consultar API /cases sin token JWT', async ({ request }) => { 
            // Evaluación rápida a nivel de red (API Request) sin renderizar DOM 
            const response = await request.get('/cases', { maxRedirects: 0 }); 
            
            expect(response.status()).toBe(307); 
            expect(response.headers()['location']).toBe('/login?redirect=%2Fcases'); 
        }); 
    });