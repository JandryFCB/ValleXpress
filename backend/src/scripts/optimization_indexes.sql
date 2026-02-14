-- =====================================================
-- ÍNDICES DE OPTIMIZACIÓN PARA ValleXpress
-- Ejecución: docker exec -i vallexpress-db psql -U postgres -d vallexpress < optimization_indexes.sql
-- =====================================================

-- =====================================================
-- ÍNDICES PARA TABLA USUARIOS
-- =====================================================
CREATE INDEX IF NOT EXISTS idx_usuarios_email ON usuarios(email);
CREATE INDEX IF NOT EXISTS idx_usuarios_tipo ON usuarios(tipo_usuario);
CREATE INDEX IF NOT EXISTS idx_usuarios_cedula ON usuarios(cedula);

-- =====================================================
-- ÍNDICES PARA TABLA PEDIDOS
-- =====================================================
CREATE INDEX IF NOT EXISTS idx_pedidos_estado ON pedidos(estado);
CREATE INDEX IF NOT EXISTS idx_pedidos_cliente ON pedidos(cliente_id);
CREATE INDEX IF NOT EXISTS idx_pedidos_vendedor ON pedidos(vendedor_id);
CREATE INDEX IF NOT EXISTS idx_pedidos_repartidor ON pedidos(repartidor_id);
CREATE INDEX IF NOT EXISTS idx_pedidos_fecha ON pedidos("fechaPedido" DESC);
CREATE INDEX IF NOT EXISTS idx_pedidos_estado_fecha ON pedidos(estado, "fechaPedido" DESC);

-- =====================================================
-- ÍNDICES PARA TABLA PRODUCTOS
-- =====================================================
CREATE INDEX IF NOT EXISTS idx_productos_vendedor ON productos(vendedor_id);
CREATE INDEX IF NOT EXISTS idx_productos_disponible ON productos(disponible);
CREATE INDEX IF NOT EXISTS idx_productos_categoria ON productos(categoria);

-- =====================================================
-- ÍNDICES PARA TABLA REPARTIDORES
-- =====================================================
CREATE INDEX IF NOT EXISTS idx_repartidores_usuario ON repartidores(usuario_id);
CREATE INDEX IF NOT EXISTS idx_repartidores_disponible ON repartidores(disponible);

-- =====================================================
-- ÍNDICES PARA TABLA VENDEDORES
-- =====================================================
CREATE INDEX IF NOT EXISTS idx_vendedores_usuario ON vendedores(usuario_id);

-- =====================================================
-- ÍNDICES PARA TABLA NOTIFICACIONES
-- =====================================================
CREATE INDEX IF NOT EXISTS idx_notificaciones_usuario ON notificaciones(usuario_id);
CREATE INDEX IF NOT EXISTS idx_notificaciones_leida ON notificaciones(leida);
CREATE INDEX IF NOT EXISTS idx_notificaciones_usuario_leida ON notificaciones(usuario_id, leida);
CREATE INDEX IF NOT EXISTS idx_notificaciones_pedido ON notificaciones(pedido_id);

-- =====================================================
-- ÍNDICES PARA TABLA DIRECCIONES
-- =====================================================
CREATE INDEX IF NOT EXISTS idx_direcciones_usuario ON direcciones(usuario_id);
CREATE INDEX IF NOT EXISTS idx_direcciones_predeterminada ON direcciones(predeterminada);

-- =====================================================
-- ÍNDICES PARA TABLA DETALLE_PEDIDO
-- =====================================================
CREATE INDEX IF NOT EXISTS idx_detalle_pedido_pedido ON "DetallePedidos"(pedido_id);
CREATE INDEX IF NOT EXISTS idx_detalle_pedido_producto ON "DetallePedidos"(producto_id);

-- =====================================================
-- VERIFICACIÓN DE ÍNDICES
-- =====================================================
SELECT 
    tablename,
    indexname,
    indexdef
FROM pg_indexes
WHERE schemaname = 'public'
AND indexname LIKE 'idx_%'
ORDER BY tablename, indexname;

-- =====================================================
-- ESTADÍSTICAS DE TABLAS (Actualizar después de crear índices)
-- =====================================================
ANALYZE usuarios;
ANALYZE pedidos;
ANALYZE productos;
ANALYZE repartidores;
ANALYZE vendedores;
ANALYZE notificaciones;
ANALYZE direcciones;
ANALYZE "DetallePedidos";

-- =====================================================
-- MOSTRAR TAMAÑO DE ÍNDICES
-- =====================================================
SELECT 
    pg_size_pretty(pg_relation_size(indexrelid)) AS size,
    indexrelname AS index_name
FROM pg_stat_user_indexes
WHERE indexrelname LIKE 'idx_%'
ORDER BY pg_relation_size(indexrelid) DESC;
