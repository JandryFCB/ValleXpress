const Producto = require('./producto.model');
const Vendedor = require('../vendedores/vendedor.model');



const { validationResult } = require('express-validator');



class ProductoController {
  // Crear producto
  async crear(req, res) {
    try {
      console.log('📝 [CREAR PRODUCTO] Usuario:', req.usuario.id, 'Tipo:', req.usuario.tipoUsuario);
      console.log('📝 [CREAR PRODUCTO] Datos recibidos:', req.body);

      const errors = validationResult(req);
      if (!errors.isEmpty()) {
        console.log('❌ [VALIDACIÓN] Errores de validación:', errors.array());
        return res.status(400).json({ errors: errors.array() });
      }

      // Verificar que el usuario sea vendedor
      if (req.usuario.tipoUsuario !== 'vendedor') {
        console.log('❌ [PERMISO] Usuario no es vendedor, tipo:', req.usuario.tipoUsuario);
        return res.status(403).json({
          error: 'Solo vendedores pueden crear productos'
        });
      }

      // Obtener el vendedor del usuario autenticado
      const vendedor = await Vendedor.findOne({
        where: { usuarioId: req.usuario.id }
      });

      if (!vendedor) {
        console.log('❌ [VENDEDOR] No encontrado para usuarioId:', req.usuario.id);
        return res.status(404).json({
          error: 'Debes registrar tu negocio primero'
        });
      }

      console.log('✅ [VENDEDOR] Encontrado:', vendedor.id, vendedor.nombreNegocio);

      const {
        nombre,
        descripcion,
        precio,
        imagen,
        categoria,
        disponible,
        tiempoPreparacion,
        stock,
      } = req.body;


      // Crear producto
      const producto = await Producto.create({
        vendedorId: vendedor.id,
        nombre,
        descripcion,
        precio: Number(precio),
        imagen,
        categoria,
        disponible: disponible !== undefined ? disponible : true,
        tiempoPreparacion: tiempoPreparacion || 0,
        stock: stock !== undefined ? Number(stock) : 0,
      });

      console.log('✅ [PRODUCTO CREADO]', producto.id, nombre);

      res.status(201).json({
        message: 'Producto creado exitosamente',
        producto
      });
    } catch (error) {
      console.error('❌ [ERROR AL CREAR PRODUCTO]:', error.message, error.stack);
      res.status(500).json({ error: error.message || 'Error al crear producto' });
    }
  }

  // Listar todos los productos
  async listar(req, res) {
    try {
      const productos = await Producto.findAll({
        include: [{
          model: Vendedor,
          as: 'vendedor',
          attributes: ['id', 'nombreNegocio', 'categoria']
        }],
        order: [['createdAt', 'DESC']]
      });

      res.json({ productos });
    } catch (error) {
      console.error('Error al listar productos:', error);
      res.status(500).json({ error: 'Error al obtener productos' });
    }
  }

  // Listar productos de un vendedor específico
  async listarPorVendedor(req, res) {
    try {
      const { vendedorId } = req.params;

      const productos = await Producto.findAll({
        where: { vendedorId },
        order: [['createdAt', 'DESC']]
      });

      res.json({ productos });
    } catch (error) {
      console.error('Error al listar productos:', error);
      res.status(500).json({ error: 'Error al obtener productos' });
    }
  }

  // Listar MIS productos (vendedor autenticado)
  async misProductos(req, res) {
    try {
      // Obtener el vendedor del usuario autenticado
      const vendedor = await Vendedor.findOne({
        where: { usuarioId: req.usuario.id }
      });

      if (!vendedor) {
        return res.status(404).json({
          error: 'No tienes un negocio registrado'
        });
      }

      const productos = await Producto.findAll({
        where: { vendedorId: vendedor.id },
        order: [['createdAt', 'DESC']]
      });

      res.json({ productos });
    } catch (error) {
      console.error('Error al obtener productos:', error);
      res.status(500).json({ error: 'Error al obtener productos' });
    }
  }

  // Obtener un producto por ID
  async obtenerPorId(req, res) {
    try {
      const { id } = req.params;

      const producto = await Producto.findByPk(id, {
        include: [{
          model: Vendedor,
          as: 'vendedor',
          attributes: ['id', 'nombreNegocio', 'categoria', 'calificacionPromedio']
        }]
      });

      if (!producto) {
        return res.status(404).json({ error: 'Producto no encontrado' });
      }

      res.json({ producto });
    } catch (error) {
      console.error('Error al obtener producto:', error);
      res.status(500).json({ error: 'Error al obtener producto' });
    }
  }

  // Actualizar producto
  async actualizar(req, res) {
    try {
      const { id } = req.params;

      // Obtener el vendedor del usuario autenticado
      const vendedor = await Vendedor.findOne({
        where: { usuarioId: req.usuario.id }
      });

      if (!vendedor) {
        return res.status(404).json({ error: 'Vendedor no encontrado' });
      }

      // Buscar el producto
      const producto = await Producto.findOne({
        where: {
          id,
          vendedorId: vendedor.id
        }
      });

      if (!producto) {
        return res.status(404).json({
          error: 'Producto no encontrado o no te pertenece'
        });
      }

      const {
        nombre,
        descripcion,
        precio,
        imagen,
        categoria,
        disponible,
        tiempoPreparacion,
        stock,
      } = req.body;
      const precioNum = (precio !== undefined) ? Number(precio) : undefined;
      const stockNum = (stock !== undefined) ? Number(stock) : undefined;

      await producto.update({
        ...(nombre !== undefined && { nombre }),
        ...(descripcion !== undefined && { descripcion }),
        ...(precioNum !== undefined && { precio: precioNum }),
        ...(imagen !== undefined && { imagen }),
        ...(categoria !== undefined && { categoria }),
        ...(disponible !== undefined && { disponible }),
        ...(tiempoPreparacion !== undefined && { tiempoPreparacion }),
        ...(stockNum !== undefined && { stock: stockNum }),
      });


      res.json({
        message: 'Producto actualizado exitosamente',
        producto
      });
    } catch (error) {
      console.error('Error al actualizar producto:', error);
      res.status(500).json({ error: 'Error al actualizar producto' });
    }
  }

  // Eliminar producto
  async eliminar(req, res) {
    try {
      const { id } = req.params;

      // Obtener el vendedor del usuario autenticado
      const vendedor = await Vendedor.findOne({
        where: { usuarioId: req.usuario.id }
      });

      if (!vendedor) {
        return res.status(404).json({ error: 'Vendedor no encontrado' });
      }

      // Buscar el producto
      const producto = await Producto.findOne({
        where: {
          id,
          vendedorId: vendedor.id
        }
      });

      if (!producto) {
        return res.status(404).json({
          error: 'Producto no encontrado o no te pertenece'
        });
      }

      await producto.destroy();

      res.json({ message: 'Producto eliminado exitosamente' });
    } catch (error) {
      console.error('Error al eliminar producto:', error);
      res.status(500).json({ error: 'Error al eliminar producto' });
    }
  }
  // Cambiar disponibilidad del producto (ON / OFF)
  async cambiarDisponible(req, res) {
    try {
      const { id } = req.params;
      const { disponible } = req.body;

      if (typeof disponible !== 'boolean') {
        return res.status(400).json({ error: 'Disponible debe ser boolean' });
      }

      // Obtener el vendedor del usuario autenticado
      const vendedor = await Vendedor.findOne({
        where: { usuarioId: req.usuario.id }
      });

      if (!vendedor) {
        return res.status(404).json({ error: 'Vendedor no encontrado' });
      }

      // Buscar producto del vendedor
      const producto = await Producto.findOne({
        where: {
          id,
          vendedorId: vendedor.id
        }
      });

      if (!producto) {
        return res.status(404).json({
          error: 'Producto no encontrado o no te pertenece'
        });
      }

      producto.disponible = disponible;
      await producto.save();

      res.json({
        message: 'Disponibilidad actualizada',
        producto
      });
    } catch (error) {
      console.error('Error al cambiar disponible:', error);
      res.status(500).json({ error: 'Error al cambiar disponibilidad' });
    }
  }

}

module.exports = new ProductoController();
