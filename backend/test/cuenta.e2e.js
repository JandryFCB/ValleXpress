// Prueba de extremo a extremo de DIRECCIONES y TELÉFONOS sobre las tablas nuevas (database/migraciones).
// Uso:  npm run test:cuenta   (desde la carpeta backend, con Docker/Postgres en marcha)
// Crea su PROPIA base temporal, levanta el servidor contra ella y al terminar borra todo. NO toca la base de desarrollo.
const crearArnes = require('./arnes');

const t = crearArnes({ puerto: 3098, bd: 'vallexpress_test_cuenta' });
const { check, seccion, api } = t;
const VIGENTE = "'2999-12-31 00:00:00-05'";
const dir = (extra = {}) => ({ direccion: 'Av. Principal 123 y Calle 2', latitud: -3.2581, longitud: -78.5516, ...extra });

(async () => {
  let q;
  try {
    ({ q } = await t.iniciar());
    const ana = await t.registrar('ana@test.com', 'Ana', 'Pérez', 'cliente');
    const luis = await t.registrar('luis@test.com', 'Luis', 'Mora', 'cliente');
    const A = ana.token; const L = luis.token;
    const idA = ana.usuario.id; const idL = luis.usuario.id;

    seccion('1. Tipos de dirección y acceso');
    let r = await api('GET', '/api/direcciones/tipos', null, A);
    check('tipos: casa, trabajo, familiar y otro (sin el local del negocio)', r.status === 200 && r.body.tipos.map((x) => x.codigo).join() === 'DOM,TRA,FAM,OTR' && r.body.tipos[0].descripcion === 'Casa', JSON.stringify(r.body));
    r = await api('GET', '/api/direcciones');
    check('sin token: 401', r.status === 401);
    r = await api('GET', '/api/direcciones/predeterminada', null, A);
    check('sin direcciones: predeterminada = 404 con { direccion: null }', r.status === 404 && r.body.direccion === null);
    r = await api('GET', '/api/direcciones', null, A);
    check('sin direcciones: lista vacía', r.status === 200 && r.body.direcciones.length === 0);

    seccion('2. Crear direcciones');
    r = await api('POST', '/api/direcciones', dir({ nombre: 'Mi casa', referencia: 'Portón verde' }), A);
    check('crear: 201 con id numérico, tipo DOM por defecto y NO predeterminada', r.status === 201 && Number.isInteger(r.body.direccion.id) && r.body.direccion.tipo === 'DOM' && r.body.direccion.esPredeterminada === false, JSON.stringify(r.body));
    const d1 = r.body.direccion;
    check('devuelve latitud/longitud como números y el usuario dueño', typeof d1.latitud === 'number' && d1.latitud === -3.2581 && d1.usuarioId === idA);
    r = await api('POST', '/api/direcciones', dir({ nombre: 'Oficina', tipo: 'tra', esPredeterminada: true }), A);
    const d2 = r.body.direccion;
    check('segunda con tipo en minúsculas y predeterminada: 201, tipo TRA', r.status === 201 && d2.tipo === 'TRA' && d2.esPredeterminada === true);
    r = await api('POST', '/api/direcciones', dir({ nombre: 'Casa de mamá', tipo: 'FAM', esPredeterminada: true }), A);
    const d3 = r.body.direccion;
    check('tercera predeterminada: la anterior deja de serlo (solo una)', r.status === 201 && d3.esPredeterminada === true && (await api('GET', '/api/direcciones', null, A)).body.direcciones.filter((x) => x.esPredeterminada).length === 1);
    r = await api('GET', '/api/direcciones/predeterminada', null, A);
    check('GET predeterminada devuelve la tercera', r.status === 200 && r.body.direccion.id === d3.id);
    r = await api('GET', '/api/direcciones', null, A);
    check('la lista trae la predeterminada primero y luego las más recientes', r.body.direcciones.map((x) => x.id).join() === [d3.id, d2.id, d1.id].join(), r.body.direcciones.map((x) => x.id).join());

    seccion('3. Validación');
    r = await api('POST', '/api/direcciones', { latitud: 1, longitud: 1 }, A);
    check('sin dirección: 400', r.status === 400 && /dirección es requerida/.test(r.body.error));
    r = await api('POST', '/api/direcciones', dir({ latitud: 200 }), A);
    check('latitud fuera de rango: 400', r.status === 400 && /Latitud/.test(r.body.error));
    r = await api('POST', '/api/direcciones', { direccion: 'x' }, A);
    check('sin coordenadas: 400 (la ubicación es obligatoria)', r.status === 400);
    r = await api('POST', '/api/direcciones', dir({ tipo: 'XXX' }), A);
    check('tipo desconocido: 400', r.status === 400 && /tipo debe ser/.test(r.body.error));
    r = await api('POST', '/api/direcciones', dir({ tipo: 'LOC' }), A);
    check('el cliente NO puede crear un "local de negocio" (LOC): 400', r.status === 400);
    r = await api('POST', '/api/direcciones', dir({ direccion: 'x'.repeat(501) }), A);
    check('dirección demasiado larga: 400', r.status === 400);
    r = await api('PUT', '/api/direcciones/abc', { nombre: 'x' }, A);
    check('id no numérico: 400', r.status === 400 && /ID de dirección inválido/.test(r.body.error));

    seccion('4. Editar, predeterminada y borrar');
    r = await api('PUT', `/api/direcciones/${d1.id}`, { nombre: 'Casa nueva', tipo: 'OTR', instrucciones: 'Tocar el timbre' }, A);
    check('editar: 200 con los cambios', r.status === 200 && r.body.direccion.nombre === 'Casa nueva' && r.body.direccion.tipo === 'OTR' && r.body.direccion.instrucciones === 'Tocar el timbre');
    check('editar no cambia lo que no se envió (dirección y coordenadas)', r.body.direccion.direccion === d1.direccion && r.body.direccion.latitud === d1.latitud);
    check('createdAt se conserva (primera versión) y updatedAt es posterior', new Date(r.body.direccion.createdAt) <= new Date(r.body.direccion.updatedAt) && r.body.direccion.createdAt === d1.createdAt, `${r.body.direccion.createdAt} / ${d1.createdAt}`);
    let h = await q(`SELECT versioncontrol v, nombre, fhasta, cusuario_modificacion m FROM tpersonadirecciones WHERE cdireccion=$1 ORDER BY fdesde`, [d1.id]);
    check('el historial queda en la MISMA tabla: v0 cerrada y v1 vigente (2999) con quién la cambió', h.length === 2 && h[0].v === 0 && h[0].nombre === 'Mi casa' && h[1].v === 1 && h[1].nombre === 'Casa nueva' && new Date(h[1].fhasta).getUTCFullYear() === 2999 && h[1].m === idA, JSON.stringify(h));
    r = await api('PATCH', `/api/direcciones/${d1.id}/predeterminada`, null, A);
    check('PATCH predeterminada: 200 y la otra deja de serlo', r.status === 200 && r.body.direccion.esPredeterminada === true && (await api('GET', '/api/direcciones', null, A)).body.direcciones.filter((x) => x.esPredeterminada).length === 1);
    r = await api('PUT', `/api/direcciones/${d2.id}`, { esPredeterminada: true }, A);
    check('PUT con esPredeterminada=true también la mueve', r.status === 200 && (await api('GET', '/api/direcciones/predeterminada', null, A)).body.direccion.id === d2.id);
    r = await api('PUT', `/api/direcciones/${d2.id}`, { latitud: 95 }, A);
    check('editar con latitud inválida: 400', r.status === 400);
    r = await api('DELETE', `/api/direcciones/${d3.id}`, null, A);
    check('borrar: 200', r.status === 200 && /eliminada/.test(r.body.message));
    check('ya no aparece en la lista', !(await api('GET', '/api/direcciones', null, A)).body.direcciones.some((x) => x.id === d3.id));
    h = await q(`SELECT fhasta FROM tpersonadirecciones WHERE cdireccion=$1`, [d3.id]);
    check('en la BD no queda fila vigente pero SÍ todo su historial cerrado', h.length >= 1 && h.every((x) => new Date(x.fhasta).getUTCFullYear() < 2999), JSON.stringify(h));
    r = await api('DELETE', `/api/direcciones/${d3.id}`, null, A);
    check('borrar una ya borrada: 404', r.status === 404 && r.body.code === 'DIRECCIONNOENCONTRADA');
    check('una dirección inexistente en PUT: 404', (await api('PUT', '/api/direcciones/99999999', { nombre: 'x' }, A)).status === 404);

    seccion('5. Cada usuario ve solo lo suyo');
    r = await api('GET', '/api/direcciones', null, L);
    check('Luis no ve las direcciones de Ana', r.status === 200 && r.body.direcciones.length === 0);
    check('Luis no puede editar la dirección de Ana: 404 (no revela que existe)', (await api('PUT', `/api/direcciones/${d1.id}`, { nombre: 'hack' }, L)).status === 404);
    check('Luis no puede marcarla predeterminada: 404', (await api('PATCH', `/api/direcciones/${d1.id}/predeterminada`, null, L)).status === 404);
    check('Luis no puede borrarla: 404', (await api('DELETE', `/api/direcciones/${d1.id}`, null, L)).status === 404);
    r = await api('POST', '/api/direcciones', dir({ nombre: 'Casa Luis', esPredeterminada: true }), L);
    check('la predeterminada de Luis no afecta a la de Ana', r.status === 201 && (await api('GET', '/api/direcciones/predeterminada', null, A)).body.direccion.id === d2.id);
    check('la dirección de Ana sigue intacta', (await api('GET', '/api/direcciones', null, A)).body.direcciones.find((x) => x.id === d1.id).nombre === 'Casa nueva');

    seccion('6. El local del negocio no es una dirección de entrega');
    const persona = (await q('SELECT cpersona FROM vusuarios WHERE usuario=$1', [idA]))[0].cpersona;
    const local = (await q(`INSERT INTO tpersonadirecciones (cpersona, ctipodireccion, direccion, latitud, longitud) VALUES ($1,'005','Local del negocio',-3.25,-78.55) RETURNING cdireccion`, [persona]))[0];
    check('un local (tipo 005) se creó por SQL con su código automático', Number(local.cdireccion) > 0);
    r = await api('GET', '/api/direcciones', null, A);
    check('NO aparece entre las direcciones del cliente', !r.body.direcciones.some((x) => x.id === Number(local.cdireccion)));
    check('no se puede editar ni borrar como si fuera suyo: 404', (await api('PUT', `/api/direcciones/${local.cdireccion}`, { nombre: 'x' }, A)).status === 404 && (await api('DELETE', `/api/direcciones/${local.cdireccion}`, null, A)).status === 404);
    const dobles = await q(`SELECT cpersona, count(*)::int n FROM tpersonadirecciones WHERE espredeterminada AND ctipodireccion<>'005' AND fhasta=${VIGENTE} GROUP BY cpersona HAVING count(*)>1`);
    check('la BD garantiza una sola predeterminada por persona', dobles.length === 0);
    const intento = await q(`UPDATE tpersonadirecciones SET espredeterminada=true WHERE cpersona=$1 AND fhasta=${VIGENTE}`, [persona]).then(() => 'permitido').catch((e) => e.message);
    check('y rechaza marcar dos predeterminadas a la vez (índice único)', /uqpersonadirpred/.test(intento), intento);

    seccion('7. Límite de direcciones');
    let ultimo;
    for (let i = 0; i < 18; i++) ultimo = await api('POST', '/api/direcciones', dir({ nombre: `Extra ${i}` }), A);
    check('se pueden guardar hasta 20 (el local no cuenta)', ultimo.status === 201 && (await api('GET', '/api/direcciones', null, A)).body.direcciones.length === 20);
    r = await api('POST', '/api/direcciones', dir(), A);
    check('la 21.ª: 409 LIMITEDIRECCIONES', r.status === 409 && r.body.code === 'LIMITEDIRECCIONES');

    seccion('8. Teléfonos');
    r = await api('GET', '/api/telefonos/tipos', null, A);
    check('tipos: móvil, casa, trabajo y WhatsApp', r.status === 200 && r.body.tipos.map((x) => x.codigo).join() === 'MOV,CAS,TRA,WAP' && r.body.tipos[3].descripcion === 'WhatsApp', JSON.stringify(r.body));
    r = await api('GET', '/api/telefonos', null, A);
    check('tras el registro hay 1 teléfono: el del registro, principal, móvil y con id 1', r.status === 200 && r.body.telefonos.length === 1 && r.body.telefonos[0].principal === true && r.body.telefonos[0].tipo === 'MOV' && r.body.telefonos[0].id === 1 && r.body.telefonos[0].verificado === false, JSON.stringify(r.body));
    const tel1 = r.body.telefonos[0];
    r = await api('GET', '/api/telefonos');
    check('sin token: 401', r.status === 401);
    r = await api('POST', '/api/telefonos', { numero: '0981112222', tipo: 'wap' }, A);
    check('agregar un segundo: 201, id 2, tipo WAP, NO principal', r.status === 201 && r.body.telefono.id === 2 && r.body.telefono.tipo === 'WAP' && r.body.telefono.principal === false, JSON.stringify(r.body));
    const tel2 = r.body.telefono;
    r = await api('POST', '/api/telefonos', { numero: '098 111-3333' }, A);
    check('acepta espacios y guiones (se normaliza) y el tipo por defecto es MOV', r.status === 201 && r.body.telefono.numero === '0981113333' && r.body.telefono.tipo === 'MOV', JSON.stringify(r.body));
    const tel3 = r.body.telefono;
    r = await api('POST', '/api/telefonos', { numero: '0981112222' }, A);
    check('repetir uno propio: 409 TELEFONODUPLICADO', r.status === 409 && r.body.code === 'TELEFONODUPLICADO');
    r = await api('POST', '/api/telefonos', { numero: tel1.numero }, L);
    check('repetir el de OTRA persona: 409', r.status === 409 && r.body.code === 'TELEFONODUPLICADO');
    r = await api('POST', '/api/telefonos', { numero: '12345' }, A);
    check('formato inválido: 400 con mensaje claro', r.status === 400 && /10 dígitos/.test(r.body.error));
    r = await api('POST', '/api/telefonos', { numero: '0981114444', tipo: 'XXX' }, A);
    check('tipo inválido: 400', r.status === 400);
    r = await api('PATCH', `/api/telefonos/${tel2.id}/principal`, null, A);
    check('marcar el 2 como principal: 200', r.status === 200 && r.body.telefono.principal === true);
    let lista = (await api('GET', '/api/telefonos', null, A)).body.telefonos;
    check('solo uno principal y va primero en la lista', lista.filter((x) => x.principal).length === 1 && lista[0].id === tel2.id, JSON.stringify(lista.map((x) => [x.id, x.principal])));
    const profile = (await api('GET', '/api/auth/profile', null, A)).body.usuario;
    check('el perfil muestra el teléfono principal nuevo', profile.telefono === '0981112222', profile.telefono);
    r = await api('PUT', `/api/telefonos/${tel2.id}`, { principal: false }, A);
    check('quitar el principal sin elegir otro: 400 PRINCIPALREQUERIDO', r.status === 400 && r.body.code === 'PRINCIPALREQUERIDO');
    r = await api('PUT', `/api/telefonos/${tel3.id}`, { tipo: 'CAS' }, A);
    check('cambiar el tipo: 200', r.status === 200 && r.body.telefono.tipo === 'CAS');
    await q(`UPDATE tpersonatelefonos SET fverificado=now() WHERE cpersona=$1 AND stelefono=$2 AND fhasta=${VIGENTE}`, [persona, tel3.id]);
    r = await api('PUT', `/api/telefonos/${tel3.id}`, { numero: '0981115555' }, A);
    check('cambiar el NÚMERO borra la verificación (hay que verificarlo de nuevo)', r.status === 200 && r.body.telefono.numero === '0981115555' && r.body.telefono.verificado === false);
    r = await api('PUT', `/api/telefonos/${tel3.id}`, { numero: '0981112222' }, A);
    check('cambiar a un número que ya tienes en otro registro: 409', r.status === 409);
    h = await q(`SELECT versioncontrol v, ctipotelefono tipo, numerotelefono n, cusuario_modificacion m, fhasta FROM tpersonatelefonos WHERE cpersona=$1 AND stelefono=$2 ORDER BY fdesde`, [persona, tel3.id]);
    check('el historial del teléfono: varias versiones, la última vigente y con quién la cambió', h.length >= 3 && h[h.length - 1].n === '0981115555' && new Date(h[h.length - 1].fhasta).getUTCFullYear() === 2999 && h[h.length - 1].m === idA, JSON.stringify(h.map((x) => [x.v, x.tipo, x.n])));

    seccion('9. Borrar teléfonos y límite');
    r = await api('DELETE', `/api/telefonos/${tel2.id}`, null, A);
    check('borrar el principal: 200', r.status === 200);
    lista = (await api('GET', '/api/telefonos', null, A)).body.telefonos;
    check('el más antiguo que queda pasa a ser el principal (id 1)', lista.length === 2 && lista[0].principal === true && lista[0].id === 1, JSON.stringify(lista.map((x) => [x.id, x.principal])));
    h = await q(`SELECT 1 FROM tpersonatelefonos WHERE cpersona=$1 AND stelefono=$2 AND fhasta<${VIGENTE}`, [persona, tel2.id]);
    check('el teléfono borrado sigue en el historial (copia cerrada)', h.length >= 1);
    r = await api('POST', '/api/telefonos', { numero: '0981112222' }, A);
    check('el número borrado queda libre y se puede volver a registrar', r.status === 201);
    for (const n of ['0981116666', '0981117777']) await api('POST', '/api/telefonos', { numero: n }, A);
    r = await api('POST', '/api/telefonos', { numero: '0981118888' }, A);
    check('el 6.º: 409 LIMITETELEFONOS (máximo 5)', r.status === 409 && r.body.code === 'LIMITETELEFONOS');
    const deLuis = (await api('GET', '/api/telefonos', null, L)).body.telefonos;
    check('Luis solo ve SUS teléfonos (1), no los de Ana', deLuis.length === 1 && deLuis[0].numero !== tel1.numero);
    check('el id 5 de Ana no existe para Luis: 404 al editarlo o borrarlo', (await api('PUT', '/api/telefonos/5', { tipo: 'CAS' }, L)).status === 404 && (await api('DELETE', '/api/telefonos/5', null, L)).status === 404);
    check('...y borrar uno inexistente: 404', (await api('DELETE', '/api/telefonos/99', null, A)).status === 404);

    seccion('10. Perfil y teléfono principal');
    r = await api('PUT', '/api/auth/profile', { telefono: '0987776666' }, L);
    check('cambiar el teléfono desde el perfil actualiza el principal', r.status === 200 && (await api('GET', '/api/telefonos', null, L)).body.telefonos[0].numero === '0987776666');
    const unicosVig = await q(`SELECT numerotelefono, count(*)::int n FROM tpersonatelefonos WHERE fhasta=${VIGENTE} GROUP BY numerotelefono HAVING count(*)>1`);
    check('en la BD no hay teléfonos vigentes repetidos', unicosVig.length === 0);

    await t.finalizar();
  } catch (e) {
    await t.finalizar(e);
  }
})();
