const path = require('path');
const glob = require('glob');
const { DataTypes, Sequelize } = require('sequelize');
const { sequelize } = require('./orm');

const ROOT = path.join(__dirname, '..', '..');
const PATTERN = 'src/modules/**/*.model.js';

const models = {};

// 🔹 Cargar modelos
const files = glob.sync(PATTERN, {
  cwd: ROOT,
  absolute: true,
});

for (const file of files) {
  const factory = require(file);
  const model = factory(sequelize, DataTypes);
  models[model.name] = model;
}

// 🔹 Ejecutar asociaciones UNA SOLA VEZ
for (const modelName in models) {
  if (models[modelName].associate) {
    models[modelName].associate(models);
  }
}

module.exports = {
  sequelize,
  Sequelize,
  ...models,
};
