const { Op } = require('sequelize');
const { sequelize } = require('../../config/database');
const Direccion = require('./direccion.model');




/**
 * Listar todas las direcciones del usuario autenticado
 */
async function listar(req, res) {
  try {
    const direcciones = await Direccion.findAll({
      where: { usuarioId: req.usuario.id },
      order: [['esPredeterminada', 'DESC'], ['createdAt', 'DESC']],
    });
    return res.json({ direcciones });
  } catch (e) {
    console.error('Direcciones.listar error:', e);
    return res.status(500).json({ error: 'Error al listar direcciones' });
  }
}

/**
 * Obtener la dirección predeterminada del usuario autenticado
 */
async function predeterminada(req, res) {
  try {
    const dir = await Direccion.findOne({
      where: { usuarioId: req.usuario.id, esPredeterminada: true },
    });
    if (!dir) {
      return res.status(404).json({ direccion: null });
    }
    return res.json({ direccion: dir });
  } catch (e) {
    console.error('Direcciones.predeterminada error:', e);
    return res.status(500).json({ error: 'Error al obtener predeterminada' });
  }
}


/**
 * Crear una dirección para el usuario autenticado
 * Si es_predeterminada === true, desmarca las demás del usuario
 */
async function crear(req, res) {
  const t = await sequelize.transaction();
  try {
    const { nombre, direccion, latitud, longitud, esPredeterminada } = req.body;

    if (typeof latitud === 'undefined' || typeof longitud === 'undefined') {
      await t.rollback();
      return res.status(400).json({ error: 'Latitud y longitud son requeridas' });
    }

    if (esPredeterminada === true) {
      await Direccion.update(
        { esPredeterminada: false },
        { where: { usuarioId: req.usuario.id }, transaction: t }
      );
    }

    const nueva = await Direccion.create(
      {
        usuarioId: req.usuario.id,
        nombre: nombre || null,
        direccion,
        latitud,
        longitud,
        esPredeterminada: !!esPredeterminada,
      },
      { transaction: t }
    );

    await t.commit();
    return res.status(201).json({ direccion: nueva });
  } catch (e) {
    await t.rollback();
    console.error('Direcciones.crear error:', e);
    return res.status(500).json({ error: 'Error al crear dirección' });
  }
}

/**
 * Actualizar una dirección del usuario (solo propietario)
 * Si es_predeterminada pasa a true, desmarca las demás
 */
async function actualizar(req, res) {
  const t = await sequelize.transaction();
  try {
    const { id } = req.params;
    const dir = await Direccion.findByPk(id);

    if (!dir || dir.usuarioId !== req.usuario.id) {
      await t.rollback();
      return res.status(404).json({ error: 'Dirección no encontrada' });
    }

    const { nombre, direccion, latitud, longitud, esPredeterminada } = req.body;

    if (esPredeterminada === true) {
      await Direccion.update(
        { esPredeterminada: false },
        { where: { usuarioId: req.usuario.id, id: { [Op.ne]: dir.id } }, transaction: t }
      );
    }

    await dir.update(
      {
        ...(typeof nombre !== 'undefined' ? { nombre } : {}),
        ...(typeof direccion !== 'undefined' ? { direccion } : {}),
        ...(typeof latitud !== 'undefined' ? { latitud } : {}),
        ...(typeof longitud !== 'undefined' ? { longitud } : {}),
        ...(typeof esPredeterminada !== 'undefined' ? { esPredeterminada: !!esPredeterminada } : {}),
      },
      { transaction: t }
    );

    await t.commit();
    return res.json({ direccion: dir });
  } catch (e) {
    await t.rollback();
    console.error('Direcciones.actualizar error:', e);
    return res.status(500).json({ error: 'Error al actualizar dirección' });
  }
}

/**
 * Marcar una dirección como predeterminada (desmarca las demás)
 */
async function marcarPredeterminada(req, res) {
  const t = await sequelize.transaction();
  try {
    const { id } = req.params;
    const dir = await Direccion.findByPk(id);

    if (!dir || dir.usuarioId !== req.usuario.id) {
      await t.rollback();
      return res.status(404).json({ error: 'Dirección no encontrada' });
    }

    await Direccion.update(
      { esPredeterminada: false },
      { where: { usuarioId: req.usuario.id, id: { [Op.ne]: dir.id } }, transaction: t }
    );

    await dir.update({ esPredeterminada: true }, { transaction: t });

    await t.commit();
    return res.json({ direccion: dir });
  } catch (e) {
    await t.rollback();
    console.error('Direcciones.marcarPredeterminada error:', e);
    return res.status(500).json({ error: 'Error al marcar predeterminada' });
  }
}

/**
 * Eliminar una dirección del usuario (solo propietario)
 */
async function eliminar(req, res) {
  try {
    const { id } = req.params;
    const dir = await Direccion.findByPk(id);

    if (!dir || dir.usuarioId !== req.usuario.id) {
      return res.status(404).json({ error: 'Dirección no encontrada' });
    }

    await dir.destroy();
    return res.json({ message: 'Dirección eliminada' });
  } catch (e) {
    console.error('Direcciones.eliminar error:', e);
    return res.status(500).json({ error: 'Error al eliminar dirección' });
  }
}

module.exports = {
  listar,
  crear,
  actualizar,
  eliminar,
  marcarPredeterminada,
  predeterminada,
};
