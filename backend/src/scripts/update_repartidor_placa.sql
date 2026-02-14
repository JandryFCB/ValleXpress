-- Actualizar tabla repartidores para validación de placa
-- Se ejecuta en producción para aplicar restricciones

-- 1. Primero verificar si hay placas duplicadas
SELECT placa, COUNT(*) as total 
FROM repartidores 
WHERE placa IS NOT NULL AND placa != 'No especificada'
GROUP BY placa 
HAVING COUNT(*) > 1;

-- 2. Si hay duplicados, actualizar a NULL los duplicados (mantener el primero)
-- UPDATE repartidores 
-- SET placa = NULL 
-- WHERE id IN (
--   SELECT id FROM (
--     SELECT id, ROW_NUMBER() OVER (PARTITION BY placa ORDER BY created_at) as rn
--     FROM repartidores 
--     WHERE placa IS NOT NULL
--   ) t WHERE rn > 1
-- );

-- 3. Actualizar placas vacías o 'No especificada' a NULL
UPDATE repartidores 
SET placa = NULL 
WHERE placa = '' OR placa = 'No especificada' OR placa IS NULL;

-- 4. Agregar índice único en placa (solo si no existe)
CREATE UNIQUE INDEX IF NOT EXISTS idx_repartidores_placa_unique 
ON repartidores(placa) 
WHERE placa IS NOT NULL;

-- 5. Verificar restricciones aplicadas
\d repartidores
