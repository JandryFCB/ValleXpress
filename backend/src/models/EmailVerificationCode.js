const { DataTypes } = require('sequelize');
const { sequelize } = require('../config/database');

const EmailVerificationCode = sequelize.define('EmailVerificationCode', {
  id: {
    type: DataTypes.UUID,
    defaultValue: DataTypes.UUIDV4,
    primaryKey: true
  },
  email: {
    type: DataTypes.STRING(150),
    allowNull: false,
    validate: {
      isEmail: true
    }
  },
  userId: {
    type: DataTypes.UUID,
    allowNull: true,
    field: 'user_id'
  },
  codeHash: {
    type: DataTypes.STRING(255),
    allowNull: false,
    field: 'code_hash'
  },
  expiresAt: {
    type: DataTypes.DATE,
    allowNull: false,
    field: 'expires_at'
  },
  attempts: {
    type: DataTypes.INTEGER,
    defaultValue: 0
  },
  usedAt: {
    type: DataTypes.DATE,
    allowNull: true,
    field: 'used_at'
  },
  fcmToken: {
    type: DataTypes.TEXT,
    allowNull: true,
    field: 'fcm_token'
  }
}, {

  tableName: 'email_verification_codes',
  timestamps: true,
  underscored: true,
  indexes: [
    { fields: ['email'] },
    { fields: ['user_id'] },
    { fields: ['expires_at'] }
  ]
});

module.exports = EmailVerificationCode;
