// Envuelve un handler async para que cualquier error llegue al errorHandler (sin try/catch en cada método).
module.exports = (fn) => (req, res, next) => Promise.resolve(fn(req, res, next)).catch(next);
