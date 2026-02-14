-- Tabla para códigos de verificación de email
CREATE TABLE IF NOT EXISTS email_verification_codes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email VARCHAR(150) NOT NULL,
    user_id UUID,
    code_hash VARCHAR(255) NOT NULL,
    expires_at TIMESTAMP NOT NULL,
    attempts INTEGER DEFAULT 0,
    used_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Índices para búsquedas rápidas
CREATE INDEX IF NOT EXISTS idx_email_verification_email ON email_verification_codes(email);
CREATE INDEX IF NOT EXISTS idx_email_verification_user_id ON email_verification_codes(user_id);
CREATE INDEX IF NOT EXISTS idx_email_verification_expires ON email_verification_codes(expires_at);

-- Comentarios
COMMENT ON TABLE email_verification_codes IS 'Almacena códigos de verificación de email para nuevos registros';
COMMENT ON COLUMN email_verification_codes.code_hash IS 'Hash bcrypt del código de 6 dígitos';
COMMENT ON COLUMN email_verification_codes.expires_at IS 'Fecha de expiración (30 minutos por defecto)';
COMMENT ON COLUMN email_verification_codes.used_at IS 'Fecha de uso del código (null si no usado)';
