# 🔐 Configuración de SendGrid para ValleXpress (Producción)

## Paso 1: Crear cuenta en SendGrid

1. Ve a https://sendgrid.com/
2. Clic en "Start for free"
3. Regístrate con tu email (puede ser el mismo de tu dominio)
4. Verifica tu cuenta por email

## Paso 2: Crear API Key

1. En el dashboard de SendGrid, ve a **Settings** → **API Keys**
2. Clic en **"Create API Key"**
3. Nombre: `ValleXpress Production`
4. Permisos: Selecciona **"Full Access"** o al menos **"Mail Send"**
5. Clic en **"Create & View"**
6. **¡IMPORTANTE!** Copia la API Key (empieza con `SG.`) - solo se muestra una vez

## Paso 3: Verificar Remitente (Sender Authentication)

SendGrid requiere verificar el dominio o email remitente:

### Opción A: Verificar Dominio (Recomendado)
1. Ve a **Settings** → **Sender Authentication**
2. Clic en **"Authenticate Your Domain"**
3. Selecciona tu proveedor de DNS (GoDaddy, Namecheap, etc.)
4. Sigue las instrucciones para agregar registros DNS
5. Espera 24-48h para propagación DNS

### Opción B: Verificar Email Individual (Más rápido)
1. Ve a **Settings** → **Sender Authentication**
2. Clic en **"Single Sender Verification"**
3. Clic en **"Create New Sender"**
4. Completa:
   - **From Name**: ValleXpress
   - **From Email**: noreply@vallexpress.com (o tu email)
   - **Reply To**: soporte@vallexpress.com
   - **Company Address**: Tu dirección física (requerido por ley)
5. Clic en **"Create"**
6. Revisa tu email y confirma

## Paso 4: Configurar Variables de Entorno

En tu archivo `.env` del backend, agrega:

```env
# SendGrid Configuration
SENDGRID_API_KEY=SG.tu_api_key_aqui
SMTP_FROM=noreply@vallexpress.com
```

## Paso 5: Probar el Envío

1. Reinicia el backend:
   ```bash
   cd backend
   npm restart
   # o
   pm2 restart vallexpress-api
   ```

2. En la app, ve a **Login** → **"¿Olvidaste tu contraseña?"**
3. Ingresa un email real
4. Revisa la bandeja de entrada (y spam)

## 📧 Límites de SendGrid (Plan Gratuito)

- **100 emails/día** en plan gratuito
- Para más volumen, considera el plan Essentials ($14.95/mes - 50,000 emails/mes)

## 🔧 Solución de Problemas

### Error: "Unauthorized"
- Verifica que la API Key esté correctamente copiada
- La API Key debe tener permisos de "Mail Send"

### Error: "Forbidden"
- El remitente (from) no está verificado
- Completa la verificación de sender en SendGrid

### Emails llegan a Spam
- Verifica tu dominio (no solo el email individual)
- Configura SPF y DKIM records en tu DNS
- Usa un dominio propio en lugar de @gmail.com

### No llegan los emails
- Revisa logs del backend: `pm2 logs vallexpress-api`
- Verifica que `SENDGRID_API_KEY` esté cargada: `echo $SENDGRID_API_KEY`
- Prueba con un email diferente (algunos bloquean emails de SendGrid)

## 📞 Soporte SendGrid

- Documentación: https://docs.sendgrid.com/
- Soporte: https://support.sendgrid.com/
- Estado del servicio: https://status.sendgrid.com/

---

**¡Listo!** Con esto tus usuarios recibirán códigos de recuperación en sus correos reales. 🚀
