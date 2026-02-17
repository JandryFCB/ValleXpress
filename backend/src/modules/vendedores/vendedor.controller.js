const Vendedor = require('./vendedor.model');
const Usuario = require('../auth/usuario.model');

const { validationResult } = require('express-validator');


class VendedorController {
  // Subir foto/logo de perfil (base64, igual que cliente)
  async subirLogoPerfil(req, res) {
    try {
      const { logo } = req.body;
      if (!logo) {
        return res.status(400).json({ error: 'No se proporcionó logo' });
      }
      const vendedor = await Vendedor.findOne({ where: { usuarioId: req.usuario.id } });
      if (!vendedor) {
        return res.status(404).json({ error: 'Vendedor no encontrado' });
      }
      await vendedor.update({ logo });
      res.json({
        message: 'Logo actualizado correctamente',
        logo: vendedor.logo
      });
    } catch (error) {
      console.error('Error al subir logo:', error);
      res.status(500).json({ error: 'Error al subir logo de perfil' });
    }
  }
  // Crear perfil de vendedor
  async crear(req, res) {
    try {
      const errors = validationResult(req);
      if (!errors.isEmpty()) {
        return res.status(400).json({ errors: errors.array() });
      }

      const {
        nombreNegocio,
        descripcion,
        logo,
        banner,
        categoria,
        horarioApertura,
        horarioCierre,
        diasAtencion,
        costoDelivery,
        radioCobertura
      } = req.body;

      // Verificar que el usuario sea tipo vendedor
      if (req.usuario.tipoUsuario !== 'vendedor') {
        return res.status(403).json({ 
          error: 'Solo usuarios tipo vendedor pueden crear un negocio' 
        });
      }

      // Verificar si ya tiene un vendedor registrado
      const vendedorExistente = await Vendedor.findOne({
        where: { usuarioId: req.usuario.id }
      });

      if (vendedorExistente) {
        return res.status(409).json({ 
          error: 'Ya tienes un negocio registrado' 
        });
      }

      // Crear vendedor
      const vendedor = await Vendedor.create({
        usuarioId: req.usuario.id,
        nombreNegocio,
        descripcion,
        logo,
        banner,
        categoria,
        horarioApertura,
        horarioCierre,
        diasAtencion,
        costoDelivery,
        radioCobertura
      });

      res.status(201).json({
        message: 'Negocio creado exitosamente',
        vendedor
      });
    } catch (error) {
      console.error('Error al crear vendedor:', error);
      res.status(500).json({ error: 'Error al crear negocio' });
    }
  }

  // Obtener todos los vendedores
  async listar(req, res) {
    try {
      const vendedores = await Vendedor.findAll({
        include: [{
          model: Usuario,
          as: 'usuario',
          attributes: ['id', 'nombre', 'apellido', 'email', 'telefono']
        }],
        order: [['createdAt', 'DESC']]
      });

      res.json({ vendedores });
    } catch (error) {
      console.error('Error al listar vendedores:', error);
      res.status(500).json({ error: 'Error al obtener vendedores' });
    }
  }

  // Obtener un vendedor por ID
  async obtenerPorId(req, res) {
    try {
      const { id } = req.params;

      const vendedor = await Vendedor.findByPk(id, {
        include: [{
          model: Usuario,
          as: 'usuario',
          attributes: ['id', 'nombre', 'apellido', 'email', 'telefono']
        }]
      });

      if (!vendedor) {
        return res.status(404).json({ error: 'Vendedor no encontrado' });
      }

      res.json({ vendedor });
    } catch (error) {
      console.error('Error al obtener vendedor:', error);
      res.status(500).json({ error: 'Error al obtener vendedor' });
    }
  }

  // Obtener el perfil del vendedor autenticado
  async miPerfil(req, res) {
    try {
      const vendedor = await Vendedor.findOne({
        where: { usuarioId: req.usuario.id },
        include: [{
          model: Usuario,
          as: 'usuario',
          attributes: ['id', 'nombre', 'apellido', 'email', 'telefono']
        }]
      });

      if (!vendedor) {
        return res.status(404).json({ 
          error: 'No tienes un perfil de vendedor registrado' 
        });
      }

      res.json({ vendedor });
    } catch (error) {
      console.error('Error al obtener perfil:', error);
      res.status(500).json({ error: 'Error al obtener perfil' });
    }
  }

  // Actualizar vendedor
  async actualizar(req, res) {
    try {
      const vendedor = await Vendedor.findOne({
        where: { usuarioId: req.usuario.id }
      });

      if (!vendedor) {
        return res.status(404).json({ error: 'Vendedor no encontrado' });
      }

      const {
        nombreNegocio,
        descripcion,
        logo,
        banner,
        categoria,
        horarioApertura,
        horarioCierre,
        diasAtencion,
        costoDelivery,
        radioCobertura,
        abiertoAhora
      } = req.body;

      await vendedor.update({
        ...(nombreNegocio && { nombreNegocio }),
        ...(descripcion !== undefined && { descripcion }),
        ...(logo && { logo }),
        ...(banner && { banner }),
        ...(categoria && { categoria }),
        ...(horarioApertura && { horarioApertura }),
        ...(horarioCierre && { horarioCierre }),
        ...(diasAtencion && { diasAtencion }),
        ...(costoDelivery !== undefined && { costoDelivery }),
        ...(radioCobertura && { radioCobertura }),
        ...(abiertoAhora !== undefined && { abiertoAhora })
      });

      res.json({
        message: 'Perfil actualizado exitosamente',
        vendedor
      });
    } catch (error) {
      console.error('Error al actualizar vendedor:', error);
      res.status(500).json({ error: 'Error al actualizar perfil' });
    }
  }

  // Eliminar vendedor
  async eliminar(req, res) {
    try {
      const vendedor = await Vendedor.findOne({
        where: { usuarioId: req.usuario.id }
      });

      if (!vendedor) {
        return res.status(404).json({ error: 'Vendedor no encontrado' });
      }

      await vendedor.destroy();

      res.json({ message: 'Negocio eliminado exitosamente' });
    } catch (error) {
      console.error('Error al eliminar vendedor:', error);
      res.status(500).json({ error: 'Error al eliminar negocio' });
    }
  }

  // Actualizar ubicación del vendedor
  async actualizarUbicacion(req, res) {
    try {
      const { latitud, longitud } = req.body;

      if (latitud === undefined || longitud === undefined) {
        return res.status(400).json({ 
          error: 'Latitud y longitud son requeridas' 
        });
      }

      const vendedor = await Vendedor.findOne({
        where: { usuarioId: req.usuario.id }
      });

      if (!vendedor) {
        return res.status(404).json({ error: 'Vendedor no encontrado' });
      }

      await vendedor.update({
        latitud: parseFloat(latitud),
        longitud: parseFloat(longitud)
      });

      res.json({
        message: 'Ubicación actualizada exitosamente',
        ubicacion: {
          latitud: vendedor.latitud,
          longitud: vendedor.longitud
        }
      });
    } catch (error) {
      console.error('Error al actualizar ubicación:', error);
      res.status(500).json({ error: 'Error al actualizar ubicación' });
    }
  }
}

module.exports = new VendedorController();
