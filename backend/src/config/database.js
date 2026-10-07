const { Sequelize } = require('sequelize');

// Las credenciales NUNCA van en el código: se leen del entorno (.env).
const requeridas = ['DB_HOST', 'DB_PORT', 'DB_NAME', 'DB_USER', 'DB_PASSWORD'];
const faltantes = requeridas.filter((k) => !process.env[k]);
if (faltantes.length) {
  throw new Error(`Faltan variables de entorno de la base de datos: ${faltantes.join(', ')}`);
}

const sequelize = new Sequelize({
  dialect: 'postgres',
  host: process.env.DB_HOST,
  port: Number(process.env.DB_PORT),
  database: process.env.DB_NAME,
  username: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
  logging: process.env.NODE_ENV === 'development' ? console.log : false,
  pool: {
    max: 10,
    min: 0,
    acquire: 30000,
    idle: 10000
  }
});

module.exports = { sequelize };
