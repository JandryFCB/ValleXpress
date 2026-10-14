// Prueba de extremo a extremo del CATÁLOGO: negocios, horarios, productos, imágenes y foto de perfil.
// Uso:  npm run test:catalogo   (desde la carpeta backend, con Docker/Postgres en marcha)
// Crea su PROPIA base temporal, levanta el servidor contra ella y al terminar borra todo.
const crearArnes = require('./arnes');

const t = crearArnes({ puerto: 3097, bd: 'vallexpress_test_catalogo' });
const { check, seccion, api } = t;
const VIGENTE = "'2999-12-31 00:00:00-05'";
const SEMANA = (apertura, cierre) => Array.from({ length: 7 }, (_, i) => ({ dia: i + 1, apertura, cierre }));

(async () => {
  let q;
  try {
    ({ q } = await t.iniciar());
    const png = await t.imagen(300, 300, 'png');

    seccion('1. Registro de vendedores y su negocio');
    const luis = await t.registrar('luis@test.com', 'Luis', 'Mora', 'vendedor', { nombreNegocio: 'Pizzería Luis', categoriaNegocio: '001' });
    const L = luis.token;
    check('el vendedor se registra', !!L, JSON.stringify(luis));
    let r = await api('GET', '/api/mi-negocio', null, L);
    check('al registrarse con nombre de negocio, el negocio se crea en el mismo paso', r.status === 200 && r.body.negocio.nombre === 'Pizzería Luis' && r.body.negocio.categoria.codigo === '001' && r.body.negocio.categoria.descripcion === 'Comida', JSON.stringify(r.body));
    const negL = r.body.negocio;
    check('nace aprobado (aprobación automática), cerrado y aceptando pedidos', negL.aprobacion === 'aprobado' && negL.abierto === false && negL.aceptaPedidos === true && negL.duenoId === luis.usuario.id);
    const fila = (await q(`SELECT cnegocio, cusuario, cestatusaprobacion FROM tnegocios WHERE fhasta=${VIGENTE}`))[0];
    check('en la BD: código propio (CNEGOCIO 1), dueño = el usuario, estado y fila de TNEGOCIOSESTADO', Number(fila.cnegocio) === 1 && fila.cusuario === luis.usuario.id && (await q('SELECT 1 FROM tnegociosestado WHERE cnegocio=1')).length === 1);

    const ana = await t.registrar('ana@test.com', 'Ana', 'Paz', 'vendedor');
    const A = ana.token;
    r = await api('GET', '/api/mi-negocio', null, A);
    check('vendedor registrado sin nombre de negocio: aún no tiene (404)', r.status === 404 && r.body.code === 'NEGOCIONOENCONTRADO');
    r = await api('POST', '/api/mi-negocio', { nombre: 'Panadería Ana', categoria: '004', descripcion: 'Pan fresco todos los días' }, A);
    check('lo crea después: 201', r.status === 201 && r.body.negocio.nombre === 'Panadería Ana' && r.body.negocio.categoria.descripcion === 'Panadería', JSON.stringify(r.body));
    const negA = r.body.negocio;
    r = await api('POST', '/api/mi-negocio', { nombre: 'Otro' }, A);
    check('un segundo negocio: 409 YATIENENEGOCIO', r.status === 409 && r.body.code === 'YATIENENEGOCIO');
    r = await api('POST', '/api/mi-negocio', { nombre: 'X' }, A);
    check('nombre de 1 letra: 400', r.status === 400);

    const cli = await t.registrar('cli@test.com', 'Carlos', 'Ruiz', 'cliente');
    const C = cli.token;
    r = await api('GET', '/api/mi-negocio', null, C);
    check('un cliente no tiene "mi negocio": 403', r.status === 403);
    r = await api('GET', '/api/negocios');
    check('el catálogo exige sesión: 401', r.status === 401);

    seccion('2. Categorías y datos del negocio');
    r = await api('GET', '/api/negocios/categorias', null, C);
    check('8 categorías (comida ... otros)', r.status === 200 && r.body.categorias.length === 8 && r.body.categorias[0].descripcion === 'Comida' && r.body.categorias.at(-1).codigo === '099', JSON.stringify(r.body));
    r = await api('PUT', '/api/mi-negocio', { costoEnvio: 1.5, pedidoMinimo: 5, tiempoPreparacion: 25, radioKm: 4, ruc: '1790012345001', descripcion: 'Las mejores pizzas' }, L);
    check('actualizar datos: 200', r.status === 200 && r.body.negocio.costoEnvio === 1.5 && r.body.negocio.pedidoMinimo === 5 && r.body.negocio.tiempoPreparacion === 25 && r.body.negocio.radioKm === 4 && r.body.negocio.ruc === '1790012345001', JSON.stringify(r.body));
    r = await api('PUT', '/api/mi-negocio', { ruc: '123' }, L);
    check('RUC inválido: 400', r.status === 400 && /13 dígitos/.test(r.body.error));
    r = await api('PUT', '/api/mi-negocio', { categoria: '555' }, L);
    check('categoría inválida: 400', r.status === 400);
    r = await api('PUT', '/api/mi-negocio', { costoEnvio: -1 }, L);
    check('costo de envío negativo: 400', r.status === 400);
    let h = await q(`SELECT versioncontrol v, costoenvio, cusuario_modificacion m, fhasta FROM tnegocios WHERE cnegocio=1 ORDER BY fdesde`);
    check('el cambio queda en el historial del negocio con quién lo hizo', h.length === 2 && Number(h[0].costoenvio) === 0 && Number(h[1].costoenvio) === 1.5 && h[1].m === luis.usuario.id, JSON.stringify(h));

    seccion('3. Local del negocio');
    r = await api('PUT', '/api/mi-negocio/local', { direccion: 'Av. Principal y Calle 3', referencia: 'Junto al parque', latitud: -3.25, longitud: -78.55 }, L);
    check('fijar el local: 200 con dirección y coordenadas', r.status === 200 && r.body.negocio.local.direccion === 'Av. Principal y Calle 3' && r.body.negocio.local.latitud === -3.25, JSON.stringify(r.body.negocio.local));
    const localId = r.body.negocio.local.id;
    check('en la BD es una dirección tipo 005 (local) de la persona dueña', (await q(`SELECT 1 FROM tpersonadirecciones WHERE cdireccion=$1 AND ctipodireccion='005' AND fhasta=${VIGENTE}`, [localId])).length === 1);
    r = await api('GET', '/api/direcciones', null, L);
    check('el local NO aparece entre sus direcciones de entrega', r.status === 200 && !r.body.direcciones.some((d) => d.id === localId));
    r = await api('PUT', '/api/mi-negocio/local', { direccion: 'Av. Principal y Calle 4', latitud: -3.26, longitud: -78.56 }, L);
    check('moverlo actualiza el MISMO local (queda en el historial)', r.status === 200 && r.body.negocio.local.id === localId && r.body.negocio.local.direccion === 'Av. Principal y Calle 4');
    r = await api('PUT', '/api/mi-negocio/local', { direccion: '', latitud: 1, longitud: 1 }, L);
    check('local sin dirección: 400', r.status === 400);

    seccion('4. Horarios, abrir y cerrar');
    r = await api('PUT', '/api/mi-negocio/horarios', { horarios: SEMANA('00:01', '00:00') }, L);
    check('horario de los 7 días: 200, ordenado de lunes a domingo', r.status === 200 && r.body.negocio.horarios.length === 7 && r.body.negocio.horarios[0].dia === 1 && r.body.negocio.horarios[0].apertura === '00:01', JSON.stringify(r.body.negocio?.horarios?.[0] || r.body));
    r = await api('PUT', '/api/mi-negocio/horarios', { horarios: [{ dia: 1, apertura: '25:00', cierre: '20:00' }] }, L);
    check('hora inválida: 400 con el formato esperado', r.status === 400 && /HH:MM/.test(r.body.error));
    r = await api('PUT', '/api/mi-negocio/horarios', { horarios: [{ dia: 2, cerrado: true }, { dia: 2, cerrado: true }] }, L);
    check('días repetidos: 400', r.status === 400 && /repetidos/.test(r.body.error));
    r = await api('PUT', '/api/mi-negocio/horarios', { horarios: [{ dia: 7, cerrado: true }] }, L);
    check('cerrar solo el domingo: los demás días no cambian', r.status === 200 && r.body.negocio.horarios.find((x) => x.dia === 7).cerrado === true && r.body.negocio.horarios.find((x) => x.dia === 1).cerrado === false);
    h = await q(`SELECT numerodia, count(*)::int n FROM tnegociohorarios WHERE cnegocio=1 GROUP BY numerodia ORDER BY 1`);
    check('solo el domingo tiene una versión nueva en el historial', h.find((x) => x.numerodia === 7).n === 2 && h.filter((x) => x.numerodia !== 7).every((x) => x.n === 1), JSON.stringify(h));
    await api('PUT', '/api/mi-negocio/horarios', { horarios: [{ dia: 7, apertura: '00:01', cierre: '00:00' }] }, L);
    r = await api('PATCH', '/api/mi-negocio/estado', { abierto: true }, L);
    check('abrir: abierto y "abierto ahora" (está dentro del horario)', r.status === 200 && r.body.negocio.abierto === true && r.body.negocio.abiertoAhora === true, JSON.stringify(r.body.negocio));
    r = await api('PATCH', '/api/mi-negocio/estado', {}, L);
    check('estado sin datos: 400', r.status === 400);
    check('abrir/cerrar NO crea versiones del negocio (va a TNEGOCIOSESTADO)', (await q('SELECT count(*)::int n FROM tnegocios WHERE cnegocio=1'))[0].n === 3);

    seccion('5. Logo y portada');
    r = await api('PUT', '/api/mi-negocio/logo', { imagen: png }, L);
    check('subir logo: 200 con la URL de la imagen optimizada (WebP)', r.status === 200 && /\/uploads\/logo\/[a-f0-9]+_m\.webp$/.test(r.body.negocio.logo || ''), r.body.negocio?.logo);
    const logoUrl = r.body.negocio.logo;
    const img = await fetch(logoUrl);
    check('la URL sirve la imagen (image/webp)', img.status === 200 && /image\/webp/.test(img.headers.get('content-type') || ''));
    r = await api('PUT', '/api/mi-negocio/portada', { imagen: png }, L);
    check('subir portada: 200', r.status === 200 && /\/uploads\/portada\//.test(r.body.negocio.portada || ''));
    r = await api('PUT', '/api/mi-negocio/logo', { imagen: 'esto-no-es-una-imagen' }, L);
    check('una "imagen" inválida: 400', r.status === 400 && r.body.code === 'IMAGENINVALIDA', JSON.stringify(r.body));
    r = await api('PUT', '/api/mi-negocio/logo', { imagen: png }, L);
    check('la misma imagen subida dos veces se guarda UNA sola vez', (await q(`SELECT count(*)::int n FROM tarchivos WHERE categoria='LOGO'`))[0].n === 1);

    seccion('6. El catálogo que ve el cliente');
    r = await api('GET', '/api/negocios', null, C);
    check('lista con los 2 negocios aprobados y paginación', r.status === 200 && r.body.negocios.length === 2 && r.body.pagination.total === 2, JSON.stringify(r.body.pagination));
    check('el abierto va primero y NO expone RUC ni aprobación', r.body.negocios[0].id === negL.id && r.body.negocios[0].ruc === undefined && r.body.negocios[0].aprobacion === undefined);
    r = await api('GET', '/api/negocios?categoria=004', null, C);
    check('filtrar por categoría (panadería)', r.body.negocios.length === 1 && r.body.negocios[0].id === negA.id);
    r = await api('GET', '/api/negocios?q=pizz', null, C);
    check('buscar por nombre ("pizz")', r.body.negocios.length === 1 && r.body.negocios[0].nombre === 'Pizzería Luis');
    r = await api('GET', '/api/negocios?abiertos=true', null, C);
    check('solo abiertos', r.body.negocios.length === 1 && r.body.negocios[0].abierto === true);
    r = await api('GET', '/api/negocios?categoria=abc', null, C);
    check('filtro inválido: 400', r.status === 400);
    r = await api('GET', `/api/negocios/${negL.id}`, null, C);
    check('detalle del negocio con local, horarios, logo y portada', r.status === 200 && r.body.negocio.local && r.body.negocio.horarios.length === 7 && !!r.body.negocio.logo && !!r.body.negocio.portada);
    await q(`UPDATE tnegocios SET cestatusaprobacion='001' WHERE cnegocio=$1`, [negA.id]);
    r = await api('GET', '/api/negocios', null, C);
    check('un negocio PENDIENTE no aparece en el catálogo', !r.body.negocios.some((n) => n.id === negA.id));
    check('...ni se puede abrir su detalle (404)', (await api('GET', `/api/negocios/${negA.id}`, null, C)).status === 404);
    r = await api('GET', `/api/negocios/${negA.id}`, null, A);
    check('...pero su dueño sí lo ve, con su estado de aprobación', r.status === 200 && r.body.negocio.aprobacion === 'pendiente');
    await q(`UPDATE tnegocios SET cestatusaprobacion='002' WHERE cnegocio=$1`, [negA.id]);

    seccion('7. Productos');
    r = await api('POST', '/api/mi-negocio/productos', { nombre: 'Pizza Margarita', precio: 8.5, seccion: 'Pizzas', descripcion: 'Tomate y queso', imagen: png }, L);
    check('crear producto con imagen: 201', r.status === 201 && r.body.producto.precio === 8.5 && r.body.producto.estado === 'disponible' && r.body.producto.disponible === true && /\/uploads\/producto\//.test(r.body.producto.imagen || ''), JSON.stringify(r.body));
    const pizza = r.body.producto;
    r = await api('POST', '/api/mi-negocio/productos', { nombre: 'Coca Cola', precio: 1.25, seccion: 'Bebidas' }, L);
    const cola = r.body.producto;
    r = await api('POST', '/api/mi-negocio/productos', { nombre: 'Pizza secreta', precio: 12, seccion: 'Pizzas', estado: 'oculto' }, L);
    const oculta = r.body.producto;
    check('crear sin imagen y uno oculto', !!cola && cola.imagen === null && oculta.estado === 'oculto');
    r = await api('POST', '/api/mi-negocio/productos', { nombre: 'Gratis', precio: 0 }, L);
    check('precio 0: 400', r.status === 400 && /precio/.test(r.body.error));
    r = await api('POST', '/api/mi-negocio/productos', { precio: 3 }, L);
    check('sin nombre: 400', r.status === 400);
    r = await api('POST', '/api/mi-negocio/productos', { nombre: 'X', precio: 3 }, C);
    check('un cliente no puede crear productos: 403', r.status === 403);
    r = await api('GET', `/api/negocios/${negL.id}/productos`, null, C);
    check('el menú del cliente trae los visibles (no el oculto), agrupables por sección', r.status === 200 && r.body.productos.length === 2 && !r.body.productos.some((p) => p.id === oculta.id) && r.body.secciones.join() === 'Bebidas,Pizzas', JSON.stringify(r.body.secciones));
    check('el cliente NO ve el stock', r.body.productos.every((p) => p.stock === undefined));
    r = await api('GET', '/api/mi-negocio/productos', null, L);
    check('el dueño ve los 3 (también el oculto) con stock y vendidos', r.status === 200 && r.body.productos.length === 3 && r.body.productos.every((p) => p.stock !== undefined));

    seccion('8. Estado y stock');
    r = await api('PATCH', `/api/mi-negocio/productos/${cola.id}/estado`, { estado: 'agotado' }, L);
    check('marcar agotado: sigue en el menú, pero no disponible', r.status === 200 && r.body.producto.estado === 'agotado' && r.body.producto.disponible === false);
    r = await api('PATCH', `/api/mi-negocio/productos/${cola.id}/stock`, { stock: 10 }, L);
    check('poner stock a un producto que no lo controla: 409', r.status === 409 && r.body.code === 'SINCONTROLSTOCK');
    r = await api('PUT', `/api/mi-negocio/productos/${cola.id}`, { controlaStock: true }, L);
    check('activar control de stock (con 0 unidades queda agotado)', r.status === 200 && r.body.producto.controlaStock === true && r.body.producto.estado === 'agotado');
    r = await api('PATCH', `/api/mi-negocio/productos/${cola.id}/estado`, { estado: 'disponible' }, L);
    check('marcarlo disponible sin stock: 409 SINSTOCK', r.status === 409 && r.body.code === 'SINSTOCK');
    r = await api('PATCH', `/api/mi-negocio/productos/${cola.id}/stock`, { stock: 24 }, L);
    check('reponer stock: vuelve solo a "disponible"', r.status === 200 && r.body.producto.stock === 24 && r.body.producto.estado === 'disponible' && r.body.producto.disponible === true);
    r = await api('PATCH', `/api/mi-negocio/productos/${cola.id}/stock`, { stock: 0 }, L);
    check('stock en 0: pasa solo a "agotado"', r.body.producto.estado === 'agotado');
    r = await api('PATCH', `/api/mi-negocio/productos/${cola.id}/stock`, { stock: -2 }, L);
    check('stock negativo: 400', r.status === 400);

    seccion('9. Editar, precios e historial');
    r = await api('PUT', `/api/mi-negocio/productos/${pizza.id}`, { precio: 9.25, descripcion: '' }, L);
    check('cambiar precio y borrar la descripción', r.status === 200 && r.body.producto.precio === 9.25 && r.body.producto.descripcion === null);
    h = await q('SELECT precio, versioncontrol v FROM tproductos WHERE cproducto=$1 ORDER BY fdesde', [pizza.id]);
    check('el historial guarda el precio anterior (8.50 -> 9.25)', h.length === 2 && Number(h[0].precio) === 8.5 && Number(h[1].precio) === 9.25, JSON.stringify(h));
    check('la auditoría registra el cambio de precio', (await q(`SELECT 1 FROM tauditoria WHERE accion='PRODUCTOPRECIO'`)).length === 1);
    r = await api('PUT', `/api/mi-negocio/productos/${pizza.id}/imagen`, { imagen: await t.imagen(200, 200, 'jpeg') }, L);
    check('cambiar la imagen del producto', r.status === 200 && r.body.producto.imagen !== pizza.imagen);
    r = await api('PUT', `/api/mi-negocio/productos/${pizza.id}`, { nombre: 'Robada' }, A);
    check('otro vendedor no puede editar el producto: 404', r.status === 404 && r.body.code === 'PRODUCTONOENCONTRADO');
    check('ni borrarlo: 404', (await api('DELETE', `/api/mi-negocio/productos/${pizza.id}`, null, A)).status === 404);
    r = await api('DELETE', `/api/mi-negocio/productos/${oculta.id}`, null, L);
    check('borrar: 200', r.status === 200);
    h = await q('SELECT fhasta FROM tproductos WHERE cproducto=$1', [oculta.id]);
    check('borrado: no queda fila vigente pero sí el historial', h.length >= 1 && h.every((x) => new Date(x.fhasta).getUTCFullYear() < 2999));
    check('borrar de nuevo: 404', (await api('DELETE', `/api/mi-negocio/productos/${oculta.id}`, null, L)).status === 404);

    seccion('10. Foto de perfil');
    r = await api('POST', '/api/usuarios/foto-perfil', { foto: png }, C);
    check('subir foto de perfil: 200 con su URL', r.status === 200 && /\/uploads\/perfil\//.test(r.body.data.fotoPerfil || ''), JSON.stringify(r.body));
    r = await api('GET', '/api/auth/profile', null, C);
    check('el perfil devuelve la foto', r.status === 200 && /\/uploads\/perfil\//.test(r.body.usuario.fotoPerfil || ''));
    check('la foto queda en TPERSONAS con historial', (await q('SELECT count(*)::int n FROM tpersonas WHERE cpersona=(SELECT cpersona FROM vusuarios WHERE usuario=$1)', [cli.usuario.id]))[0].n === 2);
    r = await api('POST', '/api/usuarios/foto-perfil', { foto: 'basura' }, C);
    check('foto inválida: 400', r.status === 400);

    await t.finalizar();
  } catch (e) {
    await t.finalizar(e);
  }
})();
