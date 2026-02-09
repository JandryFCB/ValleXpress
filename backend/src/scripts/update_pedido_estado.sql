-- Script para agregar 'recogido' a la restricción CHECK de estado en pedidos

-- Primero, eliminar la restricción CHECK existente
ALTER TABLE pedidos DROP CONSTRAINT IF EXISTS pedidos_estado_check;

-- Crear nueva restricción CHECK con 'recogido' incluido
ALTER TABLE pedidos ADD CONSTRAINT pedidos_estado_check 
CHECK (estado IN (
    'pendiente',
    'confirmado', 
    'preparando',
    'listo',
    'recogido',
    'en_camino',
    'entregado',
    'recibido_cliente',
    'cancelado'
));
