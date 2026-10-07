// Respuesta uniforme: { success, data } o { success:false, error:{ code, message } }
const ok = (res, data = null, status = 200) => res.status(status).json({ success: true, data });
const created = (res, data = null) => ok(res, data, 201);
const paginated = (res, items, { page, limit, total }) =>
  res.json({
    success: true,
    data: items,
    meta: { page, limit, total, totalPages: Math.ceil(total / limit) || 0 },
  });

module.exports = { ok, created, paginated };
