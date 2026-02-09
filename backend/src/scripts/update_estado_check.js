/**
 * Script para actualizar la restricción CHECK de estado en la tabla pedidos
 * Agrega 'recogido' a la lista de estados válidos
 */

const { sequelize } = require('../config/database');

async function updateEstadoCheck() {
  try {
    console.log('🔧 Actualizando restricción CHECK de estado en pedidos...');
    
    // Eliminar restricción existente si existe
    await sequelize.query(`
      ALTER TABLE pedidos DROP CONSTRAINT IF EXISTS pedidos_estado_check;
    `);
    console.log('✅ Restricción anterior eliminada (si existía)');
    
    // Crear nueva restricción con 'recogido' incluido
    await sequelize.query(`
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
    `);
    console.log('✅ Nueva restricción creada con estado "recogido" incluido');
    
    console.log('🎉 ¡Actualización completada exitosamente!');
    process.exit(0);
  } catch (error) {
    console.error('❌ Error actualizando restricción:', error.message);
    process.exit(1);
  }
}

updateEstadoCheck();
