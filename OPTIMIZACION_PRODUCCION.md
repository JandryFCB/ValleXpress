# Plan de Optimización ValleXpress - Producción

## ⚠️ IMPORTANTE: Precauciones
- Todos los cambios son backward-compatible
- No se eliminan funcionalidades existentes
- Los scripts SQL se pueden ejecutar en el contenedor Docker

---

## Fase 1: Índices de Base de Datos (Seguro)
### Objetivo:加速 búsquedas sin cambiar código

```
sql
-- Índices para pedidos (estado, cliente, vendedor, repartidor)
CREATE INDEX IF NOT EXISTS idx_pedidos_estado ON pedidos(estado);
CREATE INDEX IF NOT EXISTS idx_pedidos_cliente ON pedidos(cliente_id);
CREATE INDEX IF NOT EXISTS idx_pedidos_vendedor ON pedidos(vendedor_id);
CREATE INDEX IF NOT EXISTS idx_pedidos_repartidor ON pedidos(repartidor_id);
CREATE INDEX IF NOT EXISTS idx_pedidos_fecha ON pedidos("fechaPedido" DESC);

-- Índices para usuarios
CREATE INDEX IF NOT EXISTS idx_usuarios_email ON usuarios(email);
CREATE INDEX IF NOT EXISTS idx_usuarios_tipo ON usuarios(tipo_usuario);

-- Índices para productos
CREATE INDEX IF NOT EXISTS idx_productos_vendedor ON productos(vendedor_id);
CREATE INDEX IF NOT EXISTS idx_productos_disponible ON productos(disponible);

-- Índices para repartidores
CREATE INDEX IF NOT EXISTS idx_repartidores_disponible ON repartidores(disponible);

-- Índices para notificaciones
CREATE INDEX IF NOT EXISTS idx_notificaciones_usuario ON notificaciones(usuario_id);
CREATE INDEX IF NOT EXISTS idx_notificaciones_leida ON notificaciones(leida);

-- Índices para direcciones
CREATE INDEX IF NOT EXISTS idx_direcciones_usuario ON direcciones(usuario_id);
```

---

## Fase 2: Paginación en Backend (Seguro)
### Objetivo: Reducir carga de datos

- Agregar `limit` y `offset` a listados grandes
- 默认: 20-50 registros por página
- Endpoints afectados:
  - `GET /api/pedidos/mis-pedidos`
  - `GET /api/pedidos/vendedor/pedidos`
  - `GET /api/productos`
  - `GET /api/productos/vendedor/:id`
  - `GET /api/notificaciones`

---

## Fase 3: Optimización Frontend
### Objetivo: Reducir llamadas API innecesarias

1. **Polling menos frecuente**: De 10s → 30s
2. **Memoización**: Usar `const` y `=> const` widgets
3. **Eliminar duplicados**: Limpiar llamada dual (provider + directo)

---

## Fase 4: Notificaciones Asíncronas
### Objetivo: No bloquear respuesta API

- Mover creación de notificaciones a después del `res.json()`
- Usar `setImmediate()` o cola asíncrona

---

## Ejecución Sugerida

1. **Primero**: Ejecutar script de índices en Docker
2. **Segundo**: Deployar cambios de paginación
3. **Tercero**: Deployar cambios de frontend
4. **Cuarto**: Monitorear rendimiento

---

## Tiempo Estimado
- Índices: 5 minutos (SQL)
- Backend paginación: 30 minutos
- Frontend: 45 minutos
- Total: ~1.5 horas

---

## Rollback Plan
- Índices: `DROP INDEX IF EXISTS idx_...`
- Paginación: Valores por defecto mantienen compatibilidad
- Frontend:git revert si hay problemas
