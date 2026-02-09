# 🔧 Correcciones en Progreso - ValleXpress

## Problemas a Resolver

### 1. 📍 Ubicación Vendedor - NO PERSISTE
- [ ] Quitar fallback a constants.dart en el mapa
- [ ] Agregar botones +/- de zoom al mapa
- [ ] Verificar que el backend guarde correctamente
- [ ] Recargar datos reales al volver al perfil

### 2. 🔔 Notificaciones - NO APARECEN
- [ ] Revisar API de notificaciones
- [ ] Verificar que se creen en el backend
- [ ] Revisar pantalla de notificaciones
- [ ] Probar flujo completo

### 3. 🚴 Botón "Recogido" - NO FUNCIONA
- [ ] Revisar endpoint en backend
- [ ] Verificar llamada desde frontend
- [ ] Probar con pedido real

### 4. 🗺️ Rutas Repartidor - NO APARECEN
- [ ] Revisar servicio de pedidos asignados
- [ ] Verificar que el repartidor tenga pedidos en BD
- [ ] Agregar ubicación GPS actual del repartidor

### 5. ⚡ Optimización - App Lenta
- [ ] Agregar transiciones de página
- [ ] Optimizar carga de imágenes
- [ ] Revisar reconstrucciones innecesarias

### 6. 🟢 Indicador Online
- [ ] Agregar bolita verde en perfil vendedor
- [ ] Agregar bolita verde en perfil repartidor

### 7. 🎨 Homes Diferenciados
- [ ] Vendedor: Color naranja predominante
- [ ] Repartidor: Color azul predominante  
- [ ] Cliente: Color verde predominante

### 8. 📧 Validación Email Real
- [ ] Validar formato de email en registro
- [ ] Verificar que el email exista (opcional)
- [ ] Sistema de recuperación de contraseña

---

## Archivos a Modificar

### Backend
- `vendedor.controller.js` - Fix ubicación
- `notificacion.controller.js` - Fix notificaciones
- `pedido.controller.js` - Fix recogido
- `auth.controller.js` - Email validation

### Frontend
- `vendedor_profile_screen.dart` - Mapa + zoom + fix
- `repartidor_rutas_screen.dart` - GPS + rutas
- `notifications_screen.dart` - Fix carga
- `home_screen.dart` - Colores + transiciones
- `theme.dart` - Paleta expandida
- `main.dart` - Transiciones
- `constants.dart` - Quitar ubicaciones hardcodeadas
