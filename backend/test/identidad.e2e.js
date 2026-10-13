// Prueba de extremo a extremo de la IDENTIDAD V3: personas, usuarios, teléfonos, direcciones, imágenes y el historial
// en la misma tabla.  Uso:  npm run test:identidad
const crearArnes = require('./arnes');

const t = crearArnes({ puerto: 3094, bd: 'vallexpress_identidad' });
const { check, seccion, api } = t;

const VIGENTES = "fhasta > '2998-01-01'";          // filas vigentes (FHASTA = 2999-12-31)

(async () => {
  let q; let db;
  const falla = (sql, params) => db.query(sql, params).then(() => 'permitido').catch((e) => e.message);
  try {
    ({ q, db } = await t.iniciar());

    seccion('1. Estructura: tablas T, anclas y catálogos');
    const tablas = (await q("SELECT table_name n FROM information_schema.tables WHERE table_schema='public'")).map((x) => x.n);
    const nuevas = ['tpersonasid', 'tpersonas', 'tusuariosid', 'tusuarios', 'tpersonatelefonos', 'tdireccionesid', 'tpersonadirecciones',
      'tpersonaimagenes', 'testatusuario', 'ttipostelefono', 'ttiposdireccion', 'ttiposimagen', 'tlogmensajes', 'tlogerrores'];
    check('existen las 14 tablas nuevas (prefijo T)', nuevas.every((n) => tablas.includes(n)), nuevas.filter((n) => !tablas.includes(n)).join(','));
    check('ya no existen usuarios, histusuarios, direcciones, histdirecciones, logmensajes ni logerrores',
      ['usuarios', 'histusuarios', 'direcciones', 'histdirecciones', 'logmensajes', 'logerrores'].every((n) => !tablas.includes(n)));
    check('ninguna tabla tiene guion bajo en el nombre', tablas.every((n) => !n.includes('_')));
    check('el negocio, el repartidor, productos, cupones, pedidos y demás ya son tablas T (sin las viejas ni sus HIST)',
      ['tnegocios', 'thorariosnegocio', 'trepartidores', 'tproductos', 'tproductoimagenes', 'tcupones', 'tpedidos', 'tpedidodetalle', 'tpagos', 'tcalificaciones',
        'tnotificaciones', 'tdispositivos', 'tdocumentosusuario', 'tseguimientopedido', 'tubicacionrepartidor', 'tauditoria', 'tcodigosverificacion', 'tsesiones'].every((n) => tablas.includes(n))
      && ['vendedores', 'horariovendedor', 'repartidores', 'productos', 'pedidos', 'detallepedido', 'pagos', 'calificaciones', 'notificaciones', 'dispositivos', 'documentousuario',
        'histvendedores', 'histproductos', 'histpedidos', 'seguimientopedido', 'auditoria'].every((n) => !tablas.includes(n)));
    check('anclas de productos, cupones, pedidos y dispositivos (T...ID) con su código',
      ['tproductosid', 'tcuponesid', 'tpedidosid', 'tdispositivosid'].every((n) => tablas.includes(n)));
    const catalogos = ['roles', 'estadopedido', 'estadoproducto', 'estadopago', 'estadoaprobacion', 'metodopago', 'tipovehiculo', 'categorias', 'zonacobertura',
      'configuraciones', 'archivos', 'testatusuario', 'ttipostelefono', 'ttiposdireccion', 'ttiposimagen'];
    check('solo los 15 catálogos conservan tabla gemela HIST (ninguna tabla de datos)',
      tablas.filter((n) => n.startsWith('hist')).sort().join() === catalogos.map((n) => `hist${n}`).sort().join());
    check('TODAS las tablas y TODAS sus columnas llevan COMMENT ON (descripción)',
      (await q("SELECT count(*)::int n FROM pg_class c WHERE relnamespace='public'::regnamespace AND relkind='r' AND obj_description(c.oid) IS NULL"))[0].n === 0
      && (await q("SELECT count(*)::int n FROM pg_attribute a JOIN pg_class c ON c.oid=a.attrelid WHERE c.relnamespace='public'::regnamespace AND c.relkind='r' AND c.relname !~ '^hist' AND a.attnum>0 AND NOT a.attisdropped AND col_description(c.oid,a.attnum) IS NULL"))[0].n === 0);
    check('las tablas con historial en la misma tabla NO tienen gemela HIST', ['tpersonas', 'tusuarios', 'tpersonatelefonos', 'tpersonadirecciones', 'tpersonaimagenes'].every((n) => !tablas.includes(`hist${n}`)));
    check('catálogo TESTATUSUARIO: ACT, INA y BLQ', (await q('SELECT string_agg(cestatusuario, \',\' ORDER BY cestatusuario) s FROM testatusuario'))[0].s === 'ACT,BLQ,INA');
    check('catálogo TTIPOSTELEFONO (4) y TTIPOSIMAGEN (3)', (await q('SELECT (SELECT count(*) FROM ttipostelefono)::int a, (SELECT count(*) FROM ttiposimagen)::int b'))[0].a === 4 && (await q('SELECT count(*)::int n FROM ttiposimagen'))[0].n === 3);
    check('catálogo TTIPOSDIRECCION: DOM, TRA, FAM, OTR, LOC', (await q("SELECT string_agg(ctipodireccion, ',' ORDER BY orden) s FROM ttiposdireccion"))[0].s === 'DOM,TRA,FAM,OTR,LOC');
    check('CPERSONA es un número entero que crece solo (identidad)', (await q("SELECT data_type d FROM information_schema.columns WHERE table_name='tpersonasid' AND column_name='cpersona'"))[0].d === 'integer');

    seccion('2. Personas y usuarios');
    const ana = await t.registrar('ana@test.com', 'Ana', 'Pérez', 'cliente');
    const luis = await t.registrar('luis@test.com', 'Luis', 'Mora', 'cliente');
    const idAna = ana.usuario.id;
    const pAna = (await q('SELECT cpersona p FROM vusuarios WHERE usuario=$1', [idAna]))[0].p;
    const pLuis = (await q('SELECT cpersona p FROM vusuarios WHERE usuario=$1', [luis.usuario.id]))[0].p;
    check('la primera persona es la 1 y la siguiente la 2 (el código crece solo)', pAna === 1 && pLuis === 2, `${pAna},${pLuis}`);
    check('TPERSONAS guarda los datos de la persona y TUSUARIOS la enlaza por CPERSONA',
      (await q('SELECT p.nombres, p.email, u.cpersona, u.cestatusuario FROM tpersonas p JOIN tusuarios u ON u.cpersona=p.cpersona WHERE u.cusuario=$1', [idAna]))[0].email === 'ana@test.com');
    check('el usuario nace con estatus ACT', (await q('SELECT cestatusuario e FROM tusuarios WHERE cusuario=$1', [idAna]))[0].e === 'ACT');
    check('las anclas guardan el código: TPERSONASID (1, 2) y TUSUARIOSID (aperez, lmora)',
      (await q('SELECT count(*)::int n FROM tpersonasid'))[0].n === 2 && (await q("SELECT count(*)::int n FROM tusuariosid WHERE cusuario IN ('aperez','lmora')"))[0].n === 2);
    let r = await db.query("INSERT INTO tusuarios (cpersona, crol, clavehash) VALUES (1, '002', 'x') RETURNING cusuario");
    check('una persona puede tener otro usuario con otro rol (se genera su CUSUARIO)', r.rows[0].cusuario === 'afperez' || /^[a-z0-9]{3,30}$/.test(r.rows[0].cusuario), r.rows[0].cusuario);
    check('...pero no dos usuarios con el mismo rol', /uqtusuariosrol/.test(await falla("INSERT INTO tusuarios (cpersona, crol, clavehash) VALUES (1, '002', 'x')")));
    check('el CPERSONA de TPERSONAS no se puede cambiar', /no se puede cambiar/.test(await falla('UPDATE tpersonas SET cpersona=99 WHERE cpersona=1')));
    check('el CUSUARIO de TUSUARIOS no se puede cambiar', /no se puede cambiar/.test(await falla("UPDATE tusuarios SET cusuario='otro' WHERE cusuario='aperez'")));
    check('las anclas no se pueden modificar (CPERSONA es identidad; CUSUARIO tiene trigger)', /DEFAULT/.test(await falla('UPDATE tpersonasid SET cpersona=50 WHERE cpersona=1')) && /no se puede cambiar/.test(await falla("UPDATE tusuariosid SET cusuario='zzz' WHERE cusuario='aperez'")));
    check('estatus inexistente: la clave foránea lo rechaza', /fktusuariosestatus/.test(await falla("UPDATE tusuarios SET cestatusuario='ZZZ' WHERE cusuario='aperez'")));

    seccion('3. Historial en la MISMA tabla');
    const fAntes = (await q('SELECT fdesde FROM tpersonas WHERE cpersona=1 AND ' + VIGENTES))[0].fdesde;
    r = await api('PUT', '/api/usuarios/actualizar', { nombre: 'Ana María' }, ana.token);
    check('PUT /usuarios/actualizar: 200', r.status === 200 && r.body.data?.nombre === 'Ana María', JSON.stringify(r.body));
    let filas = await q('SELECT versioncontrol v, nombres, fdesde, fhasta, actualizadopor FROM tpersonas WHERE cpersona=1 ORDER BY fdesde');
    check('la persona tiene 2 filas: la versión 0 (cerrada) y la 1 (vigente)', filas.length === 2 && filas[0].v === 0 && filas[1].v === 1 && filas[0].nombres === 'Ana' && filas[1].nombres === 'Ana María', JSON.stringify(filas));
    check('la versión vieja conserva su FDESDE y se cierra (FHASTA) cuando nace la nueva', new Date(filas[0].fdesde).getTime() === new Date(fAntes).getTime() && new Date(filas[0].fhasta).getTime() === new Date(filas[1].fdesde).getTime());
    check('la vigente tiene FHASTA 2999-12-31 y solo hay UNA vigente', new Date(filas[1].fhasta).getUTCFullYear() === 2999 && filas.filter((x) => new Date(x.fhasta).getUTCFullYear() === 2999).length === 1);
    check('ACTUALIZADOPOR guarda quién cambió (el usuario del backend: aperez)', filas[1].actualizadopor === idAna, String(filas[1].actualizadopor));
    check('el historial NO se puede modificar: el UPDATE se ignora', (await db.query("UPDATE tpersonas SET nombres='HACK' WHERE cpersona=1 AND fhasta < '2998-01-01'")).rowCount === 0
      && (await q("SELECT count(*)::int n FROM tpersonas WHERE nombres='HACK'"))[0].n === 0);
    const antes = (await q('SELECT count(*)::int n FROM tpersonas'))[0].n;
    await db.query("UPDATE tpersonas SET nombres='Ana María' WHERE cpersona=1 AND " + VIGENTES);
    check('un UPDATE que no cambia nada NO crea versión', (await q('SELECT count(*)::int n FROM tpersonas'))[0].n === antes);
    await db.query("UPDATE tpersonas SET apellidos='Pérez Soto' WHERE cpersona=1 AND " + VIGENTES);
    filas = await q('SELECT actualizadopor a FROM tpersonas WHERE cpersona=1 AND ' + VIGENTES);
    check('editando desde SQL (Adminer/psql) ACTUALIZADOPOR guarda tu usuario de la base de datos', filas[0].a === process.env.DB_USER, String(filas[0].a));
    await db.query("UPDATE tusuarios SET ultimaconexion=now(), intentosfallidos=3 WHERE cusuario=$1", [idAna]);
    check('las columnas volátiles (ULTIMACONEXION, INTENTOSFALLIDOS) NO crean versión', (await q('SELECT count(*)::int n FROM tusuarios WHERE cusuario=$1', [idAna]))[0].n === 1);
    await db.query("UPDATE tusuarios SET intentosfallidos=0 WHERE cusuario=$1", [idAna]);
    check('dos vigentes del mismo código son imposibles', /uqtpersonasvigente/.test(await falla("INSERT INTO tpersonas (cpersona, nombres, apellidos, numdoc, email) VALUES (1, 'X', 'Y', '0000000001', 'otro@test.com')")));
    check('el correo y el documento son únicos solo entre las vigentes', /uqtpersonasemail/.test(await falla("INSERT INTO tpersonas (nombres, apellidos, numdoc, email) VALUES ('X', 'Y', '0000000002', 'ana@test.com')")));

    seccion('4. Teléfonos (TPERSONATELEFONOS)');
    let tel = await q('SELECT * FROM tpersonatelefonos WHERE cpersona=1 AND ' + VIGENTES);
    check('el registro crea el teléfono PRINCIPAL de tipo MOV', tel.length === 1 && tel[0].principal === true && tel[0].ctipotelefono === 'MOV');
    await db.query("INSERT INTO tpersonatelefonos (cpersona, ctipotelefono, numero) VALUES (1, 'CAS', '022345678')");
    check('una persona puede tener varios teléfonos con tipo (MOV, CAS...)', (await q('SELECT count(*)::int n FROM tpersonatelefonos WHERE cpersona=1 AND ' + VIGENTES))[0].n === 2);
    check('VUSUARIOS.TELEFONO muestra el principal', (await q('SELECT telefono FROM vusuarios WHERE usuario=$1', [idAna]))[0].telefono === tel[0].numero);
    check('solo UN teléfono principal por persona', /uqtpersonatelefonosprincipal/.test(await falla("INSERT INTO tpersonatelefonos (cpersona, numero, principal) VALUES (1, '0980000001', TRUE)")));
    check('un número no puede repetirse entre personas', /uqtpersonatelefonosnumero/.test(await falla("INSERT INTO tpersonatelefonos (cpersona, numero) VALUES (2, '022345678')")));
    check('tipo de teléfono inexistente: la clave foránea lo rechaza', /fktpersonatelefonostipo/.test(await falla("INSERT INTO tpersonatelefonos (cpersona, ctipotelefono, numero) VALUES (1, 'ZZZ', '0980000002')")));
    r = await api('PUT', '/api/usuarios/actualizar', { telefono: '0997770001' }, ana.token);
    filas = await q('SELECT numero, versioncontrol v, fhasta FROM tpersonatelefonos WHERE cpersona=1 AND principal ORDER BY fdesde');
    check('cambiar el teléfono por la API versiona: el número anterior queda en el historial', r.status === 200 && filas.length === 2 && filas[0].numero === tel[0].numero && filas[1].numero === '0997770001' && filas[1].v === 1, JSON.stringify(filas));
    r = await api('PUT', '/api/usuarios/actualizar', { telefono: tel[0].numero.replace(/.$/, '9') }, luis.token);
    r = await api('PUT', '/api/usuarios/actualizar', { telefono: '0997770001' }, luis.token);
    check('teléfono de otra persona: 409 TELEFONODUPLICADO', r.status === 409 && r.body.code === 'TELEFONODUPLICADO', JSON.stringify(r.body));
    await db.query("UPDATE tpersonatelefonos SET eliminadoen=now() WHERE cpersona=1 AND numero='022345678' AND " + VIGENTES);
    check('al eliminar (baja lógica) un teléfono, su número queda libre para otra persona', (await db.query("INSERT INTO tpersonatelefonos (cpersona, numero) VALUES (2, '022345678')")).rowCount === 1);
    await db.query("DELETE FROM tpersonatelefonos WHERE cpersona=2 AND numero='022345678'");
    const borrada = await q("SELECT eliminadoen, fhasta FROM tpersonatelefonos WHERE cpersona=2 AND numero='022345678'");
    check('un DELETE físico deja la copia cerrada en la misma tabla (con ELIMINADOEN)', borrada.length === 1 && borrada[0].eliminadoen !== null && new Date(borrada[0].fhasta).getUTCFullYear() < 2999);

    seccion('5. Direcciones (TPERSONADIRECCIONES)');
    r = await api('POST', '/api/direcciones', { nombre: 'Casa', direccion: 'Av. Amazonas N1-23', latitud: -0.18, longitud: -78.47, esPredeterminada: true }, ana.token);
    const dir = r.body.direccion?.id;
    check('POST /direcciones: 201 con id DIR-000001', r.status === 201 && dir === 'DIR-000001', JSON.stringify(r.body));
    filas = await q('SELECT cpersona, ctipodireccion tipo, alias FROM tpersonadirecciones WHERE cdireccion=$1', [dir]);
    check('la dirección es de la PERSONA (CPERSONA=1) y su tipo por defecto es DOM (domicilio)', filas.length === 1 && filas[0].cpersona === 1 && filas[0].tipo === 'DOM' && filas[0].alias === 'Casa');
    check('el código DIR-000001 queda en el ancla TDIRECCIONESID', (await q('SELECT count(*)::int n FROM tdireccionesid WHERE cdireccion=$1', [dir]))[0].n === 1);
    await db.query("UPDATE tpersonadirecciones SET ctipodireccion='TRA' WHERE cdireccion=$1 AND " + VIGENTES, [dir]);
    check('el tipo de dirección se cambia con el catálogo (TRA = trabajo) y versiona', (await q('SELECT count(*)::int n FROM tpersonadirecciones WHERE cdireccion=$1', [dir]))[0].n === 2);
    check('tipo de dirección inexistente: la clave foránea lo rechaza', /fktpersonadireccionestipo/.test(await falla("UPDATE tpersonadirecciones SET ctipodireccion='ZZZ' WHERE cdireccion=$1 AND " + VIGENTES, [dir])));
    r = await api('PUT', `/api/direcciones/${dir}`, { nombre: 'Oficina', referencia: 'Piso 3' }, ana.token);
    check('PUT /direcciones/:id: 200 con los datos nuevos', r.status === 200 && r.body.direccion.nombre === 'Oficina' && r.body.direccion.referencia === 'Piso 3', JSON.stringify(r.body));
    r = await api('GET', '/api/direcciones', null, ana.token);
    check('la API lista SOLO la versión vigente (1 dirección, no una por versión)', r.body.direcciones.length === 1 && r.body.direcciones[0].nombre === 'Oficina');
    check('el historial de la dirección queda en la tabla (3 filas)', (await q('SELECT count(*)::int n FROM tpersonadirecciones WHERE cdireccion=$1', [dir]))[0].n === 3);
    check('SEGURIDAD: otro usuario no ve ni modifica la dirección (404)', (await api('PUT', `/api/direcciones/${dir}`, { nombre: 'Hack' }, luis.token)).status === 404 && (await api('GET', '/api/direcciones', null, luis.token)).body.direcciones.length === 0);
    check('los pedidos apuntan al ancla TDIRECCIONESID (no cambia al versionar la dirección)',
      (await q("SELECT ccu.table_name t FROM information_schema.table_constraints tc JOIN information_schema.constraint_column_usage ccu ON ccu.constraint_name=tc.constraint_name WHERE tc.constraint_name='fktpedidosdireccion'"))[0].t === 'tdireccionesid');

    seccion('6. Imágenes (TPERSONAIMAGENES)');
    r = await api('POST', '/api/usuarios/foto-perfil', { foto: await t.imagen(300, 300) }, ana.token);
    check('foto de perfil: 200 con URL', r.status === 200 && /_m\.webp$/.test(r.body.data?.fotoPerfil || ''), JSON.stringify(r.body).slice(0, 120));
    let img = await q("SELECT cimagen, archivo, ctipoimagen FROM tpersonaimagenes WHERE cpersona=1 AND " + VIGENTES);
    check('queda UNA imagen vigente de tipo PER (perfil) atada a la persona', img.length === 1 && img[0].ctipoimagen === 'PER' && /^ARC-/.test(img[0].archivo));
    const arc1 = img[0].archivo;
    r = await api('POST', '/api/usuarios/foto-perfil', { foto: await t.imagen(400, 400, 'jpeg') }, ana.token);
    img = await q('SELECT cimagen, archivo, versioncontrol v, fhasta FROM tpersonaimagenes WHERE cpersona=1 ORDER BY fdesde');
    check('una foto nueva NO se pierde la anterior: mismo CIMAGEN, versión cerrada con el ARCHIVO viejo', img.length === 2 && img[0].cimagen === img[1].cimagen && img[0].archivo === arc1 && img[1].archivo !== arc1 && img[1].v === 1, JSON.stringify(img));
    check('VUSUARIOS.FOTO apunta a la imagen vigente', (await q('SELECT foto FROM vusuarios WHERE usuario=$1', [idAna]))[0].foto === img[1].archivo);
    check('solo una imagen vigente por persona y tipo', /uqtpersonaimagenestipo/.test(await falla("INSERT INTO tpersonaimagenes (cpersona, ctipoimagen, archivo) VALUES (1, 'PER', $1)", [arc1])));
    check('se permiten imágenes de otro tipo (POR = portada) para la misma persona', (await db.query("INSERT INTO tpersonaimagenes (cpersona, ctipoimagen, archivo) VALUES (1, 'POR', $1)", [arc1])).rowCount === 1);
    check('el archivo debe existir (clave foránea a ARCHIVOS)', /fktpersonaimagenesarchivo/.test(await falla("INSERT INTO tpersonaimagenes (cpersona, ctipoimagen, archivo) VALUES (2, 'PER', 'ARC-999999')")));
    r = await api('GET', '/api/usuarios/perfil', null, ana.token);
    check('el perfil devuelve fotoPerfil (URL) y el formato de la app no cambió', r.status === 200 && /_m\.webp$/.test(r.body.data.fotoPerfil) && r.body.data.nombre === 'Ana María' && r.body.data.telefono === '0997770001', JSON.stringify(r.body).slice(0, 200));

    seccion('7. Estatus de la cuenta (ACT / INA / BLQ)');
    await db.query("UPDATE tusuarios SET cestatusuario='BLQ' WHERE cusuario=$1", [idAna]);
    r = await api('POST', '/api/auth/login', { email: 'ana@test.com', password: 'secreto1' });
    check('estatus BLQ: no puede iniciar sesión (403)', r.status === 403 && r.body.code === 'CUENTADESACTIVADA', JSON.stringify(r.body));
    check('el cambio de estatus quedó versionado (la fila ACT queda cerrada)', (await q("SELECT string_agg(cestatusuario, ',' ORDER BY fdesde) s FROM tusuarios WHERE cusuario=$1", [idAna]))[0].s === 'ACT,BLQ');
    await db.query("UPDATE tusuarios SET cestatusuario='INA' WHERE cusuario=$1", [idAna]);
    check('estatus INA: tampoco inicia sesión', (await api('POST', '/api/auth/login', { email: 'aperez', password: 'secreto1' })).status === 403);
    await db.query("UPDATE tusuarios SET cestatusuario='ACT' WHERE cusuario=$1", [idAna]);
    check('vuelve a ACT: inicia sesión con el usuario (aperez) o el correo', (await api('POST', '/api/auth/login', { email: 'aperez', password: 'secreto1' })).status === 200 && (await api('POST', '/api/auth/login', { email: 'ana@test.com', password: 'secreto1' })).status === 200);

    seccion('8. Vista VUSUARIOS (consultar e insertar sin comillas)');
    check('SELECT * FROM VUSUARIOS funciona sin comillas', (await db.query('SELECT count(*)::int n FROM VUSUARIOS')).rows[0].n >= 2);
    check('VUSUARIOS muestra solo lo vigente (igual a TUSUARIOS vigente)', (await q('SELECT (SELECT count(*) FROM vusuarios)::int a, (SELECT count(*) FROM tusuarios WHERE ' + VIGENTES + ')::int b'))[0].a === (await q('SELECT count(*)::int b FROM tusuarios WHERE ' + VIGENTES))[0].b);
    r = await db.query("INSERT INTO VUSUARIOS (ROL, NOMBRES, APELLIDOS, EMAIL, TELEFONO, NUMDOC, CLAVEHASH) VALUES ('001', 'Rosa Elena', 'Vega Paz', 'rosa@test.com', '0981112223', '1700000099', 'h') RETURNING usuario, cpersona");
    const pRosa = r.rows[0].cpersona;       // las secuencias pueden saltar números tras un INSERT fallido: es normal
    check('INSERT en VUSUARIOS reparte los datos y genera el usuario (rvega) y el CPERSONA (> 2)', r.rows[0].usuario === 'rvega' && pRosa > 2, JSON.stringify(r.rows[0]));
    check('...en TPERSONAS, TUSUARIOS y TPERSONATELEFONOS', (await q(`SELECT (SELECT count(*) FROM tpersonas WHERE cpersona=${pRosa})::int a, (SELECT count(*) FROM tusuarios WHERE cusuario='rvega')::int b, (SELECT count(*) FROM tpersonatelefonos WHERE cpersona=${pRosa} AND principal)::int c`)).every((x) => x.a === 1 && x.b === 1 && x.c === 1));
    await db.query("UPDATE VUSUARIOS SET ACEPTAPROMO=TRUE WHERE usuario='rvega'");
    check('UPDATE en VUSUARIOS solo versiona la tabla que cambió (TUSUARIOS sí, TPERSONAS no)', (await q("SELECT count(*)::int n FROM tusuarios WHERE cusuario='rvega'"))[0].n === 2 && (await q('SELECT count(*)::int n FROM tpersonas WHERE cpersona=$1', [pRosa]))[0].n === 1);
    check('el USUARIO de VUSUARIOS no se puede cambiar', /no se puede cambiar/.test(await falla("UPDATE VUSUARIOS SET USUARIO='otro' WHERE usuario='rvega'")));

    seccion('8B. API de teléfonos y tipos de dirección');
    const tk = (await t.registrar('tel@test.com', 'Tomás', 'Lara', 'cliente')).token;
    const tk2 = (await t.registrar('tel2@test.com', 'Rita', 'Soto', 'cliente')).token;
    r = await api('GET', '/api/telefonos/tipos', null, tk);
    check('GET /telefonos/tipos: MOV, CAS, TRA, WAP con descripción', r.status === 200 && r.body.tipos.map((x) => x.codigo).join() === 'MOV,CAS,TRA,WAP' && r.body.tipos[0].descripcion === 'MOVIL', JSON.stringify(r.body));
    check('sin token: 401', (await api('GET', '/api/telefonos')).status === 401);
    r = await api('GET', '/api/telefonos', null, tk);
    check('el teléfono del registro ya aparece, es principal y de tipo MOV', r.status === 200 && r.body.telefonos.length === 1 && r.body.telefonos[0].principal === true && r.body.telefonos[0].tipo === 'MOV');
    const telRegistro = r.body.telefonos[0].id;
    r = await api('POST', '/api/telefonos', { numero: '0988111222', tipo: 'wap' }, tk);
    const telNuevo = r.body.telefono?.id;
    check('POST /telefonos: 201, el tipo se normaliza (WAP) y no es principal', r.status === 201 && r.body.telefono.tipo === 'WAP' && r.body.telefono.principal === false, JSON.stringify(r.body));
    check('número inválido: 400 · tipo inválido: 400 · repetido: 409 TELEFONODUPLICADO',
      (await api('POST', '/api/telefonos', { numero: '123' }, tk)).status === 400 && (await api('POST', '/api/telefonos', { numero: '0988333444', tipo: 'XXX' }, tk)).status === 400
      && (await api('POST', '/api/telefonos', { numero: '0988111222' }, tk2)).body.code === 'TELEFONODUPLICADO');
    r = await api('PATCH', `/api/telefonos/${telNuevo}/principal`, null, tk);
    check('PATCH /:id/principal: el nuevo pasa a principal y el anterior deja de serlo (uno solo)',
      r.status === 200 && r.body.telefono.principal === true && (await q('SELECT count(*)::int n FROM tpersonatelefonos WHERE principal AND ' + VIGENTES + ' AND numero IN ($1,$2)', ['0988111222', '0988111222']))[0].n === 1
      && (await api('GET', '/api/telefonos', null, tk)).body.telefonos.filter((x) => x.principal).length === 1);
    check('VUSUARIOS.TELEFONO ya muestra el nuevo principal', (await q('SELECT telefono FROM vusuarios WHERE email=$1', ['tel@test.com']))[0].telefono === '0988111222');
    r = await api('PUT', `/api/telefonos/${telNuevo}`, { numero: '0988555666', tipo: 'TRA' }, tk);
    check('PUT /:id cambia número y tipo; el número nuevo queda sin verificar y el cambio versionado',
      r.status === 200 && r.body.telefono.numero === '0988555666' && r.body.telefono.tipo === 'TRA' && r.body.telefono.verificado === false
      && (await q('SELECT count(*)::int n FROM tpersonatelefonos WHERE ctelefono=$1 AND NOT (' + VIGENTES + ')', [telNuevo]))[0].n >= 1);
    check('no se puede quitar el principal sin marcar otro (400)', (await api('PUT', `/api/telefonos/${telNuevo}`, { principal: false }, tk)).body.code === 'PRINCIPALREQUERIDO');
    check('SEGURIDAD: otro usuario no ve ni toca mi teléfono (404)', (await api('PUT', `/api/telefonos/${telNuevo}`, { tipo: 'MOV' }, tk2)).status === 404 && (await api('DELETE', `/api/telefonos/${telNuevo}`, null, tk2)).status === 404);
    r = await api('DELETE', `/api/telefonos/${telNuevo}`, null, tk);
    check('DELETE del principal: 200 y el que queda pasa a ser el principal', r.status === 200 && (await api('GET', '/api/telefonos', null, tk)).body.telefonos.length === 1
      && (await api('GET', '/api/telefonos', null, tk)).body.telefonos[0].id === telRegistro && (await api('GET', '/api/telefonos', null, tk)).body.telefonos[0].principal === true);
    check('borrado lógico: la fila sigue con ELIMINADOEN y el número queda libre para otra persona',
      (await q('SELECT count(*)::int n FROM tpersonatelefonos WHERE ctelefono=$1 AND eliminadoen IS NOT NULL', [telNuevo]))[0].n >= 1 && (await api('POST', '/api/telefonos', { numero: '0988555666' }, tk2)).status === 201);
    for (const n of ['0970000001', '0970000002', '0970000003', '0970000004']) await api('POST', '/api/telefonos', { numero: n }, tk);
    check('máximo 5 teléfonos por persona: el sexto da 409 LIMITETELEFONOS', (await api('POST', '/api/telefonos', { numero: '0970000009' }, tk)).body.code === 'LIMITETELEFONOS');

    r = await api('GET', '/api/direcciones/tipos', null, tk);
    check('GET /direcciones/tipos: DOM, TRA, FAM, OTR (LOC no se ofrece al cliente)', r.status === 200 && r.body.tipos.map((x) => x.codigo).join() === 'DOM,TRA,FAM,OTR', JSON.stringify(r.body));
    r = await api('POST', '/api/direcciones', { nombre: 'Oficina', tipo: 'tra', direccion: 'Av. 6 de Diciembre', latitud: -0.17, longitud: -78.48 }, tk);
    check('crear con tipo "tra": 201 y se guarda TRA', r.status === 201 && r.body.direccion.tipo === 'TRA' && (await q('SELECT ctipodireccion t FROM tpersonadirecciones WHERE cdireccion=$1', [r.body.direccion.id]))[0].t === 'TRA', JSON.stringify(r.body));
    check('tipo LOC o inexistente: 400 (el local lo maneja el negocio)', (await api('POST', '/api/direcciones', { tipo: 'LOC', direccion: 'x', latitud: 1, longitud: 1 }, tk)).status === 400 && (await api('POST', '/api/direcciones', { tipo: 'ZZZ', direccion: 'x', latitud: 1, longitud: 1 }, tk)).status === 400);
    r = await api('PUT', `/api/direcciones/${r.body.direccion.id}`, { tipo: 'FAM' }, tk);
    check('PUT cambia el tipo a FAM', r.status === 200 && r.body.direccion.tipo === 'FAM');
    await db.query("INSERT INTO tpersonadirecciones (cpersona, ctipodireccion, domicilio, latitud, longitud) SELECT cpersona, 'LOC', 'Local de prueba', 1, 1 FROM vusuarios WHERE email='tel@test.com'");
    check('una dirección LOC (local de negocio) no aparece en las direcciones del cliente', (await api('GET', '/api/direcciones', null, tk)).body.direcciones.every((d) => d.tipo !== 'LOC'));

    seccion('9. Logs con el nombre nuevo');
    check('TLOGMENSAJES guarda el fallo del correo (ADVERTENCIA)', (await q("SELECT count(*)::int n FROM tlogmensajes WHERE modulo='CORREO' AND nivel='ADVERTENCIA'"))[0].n >= 1);
    check('PURGARLOGS() sigue funcionando con las tablas T', typeof (await q('SELECT * FROM PURGARLOGS()'))[0].mensajesborrados !== 'undefined');
    check('el esquema no tiene UUID ni nombres con mayúsculas guardadas', (await q("SELECT count(*)::int n FROM information_schema.columns WHERE table_schema='public' AND (data_type='uuid' OR column_name<>lower(column_name) OR table_name<>lower(table_name))"))[0].n === 0);
  } catch (e) {
    await t.finalizar(e);
    return;
  }
  await t.finalizar();
})();
