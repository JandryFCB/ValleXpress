-- Agregar columna fcm_token a la tabla email_verification_codes
-- para guardar el token FCM temporalmente durante el registro

ALTER TABLE email_verification_codes 
ADD COLUMN IF NOT EXISTS fcm_token TEXT;

-- Crear índice para búsquedas rápidas por fcm_token (opcional)
CREATE INDEX IF NOT EXISTS idx_email_verification_fcm_token 
ON email_verification_codes(fcm_token) 
WHERE fcm_token IS NOT NULL;

COMMENT ON COLUMN email_verification_codes.fcm_token IS 
'Token FCM del dispositivo para enviar notificación push durante verificación de email';
