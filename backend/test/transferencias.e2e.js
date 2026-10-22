// Prueba de extremo a extremo del PAGO POR TRANSFERENCIA del cliente al negocio:
//   * el negocio registra sus cuentas (sin cuentas no se puede elegir transferencia)
//   * el cliente ve las cuentas cuando el negocio confirma, sube el comprobante y el negocio lo confirma o lo rechaza
//   * sin pago el negocio no prepara; sin pago en camino el negocio puede rechazar y el cliente cancelar
//   * si el cliente no sube el comprobante a tiempo, el vigilante cancela el pedido
// Uso:  npm run test:transferencias   (desde la carpeta backend, con Docker/Postgres en marcha)
const path = require('path');
const { spawnSync } = require('child_process');
const crearArnes = require('./arnes');

const BD = 'vallexpress_test_transferencias';

const t = crearArnes({ puerto: 3096, bd: BD, env: { VENCIMIENTO_CADA_MS: '300' } });
const { check, seccion, api } = t;
const dormir = (ms) => new Promise((r) => setTimeout(r, ms));

(async () => {
  let q;
  try {
    ({ q } = await t.iniciar());
    const estado = async (id) => (await q("SELECT cestatuspedido AS e, espagado AS pagado, motivocancelacion AS m FROM tpedidos WHERE cpedido=$1 AND fhasta='2999-12-31 00:00:00-05'", [id]))[0];
    const avisos = async (usuario, tipo, pedido) => (await q('SELECT mensaje FROM tnotificaciones WHERE cusuario=$1 AND tipo=$2 AND cpedido=$3', [usuario, tipo, pedido])).map((f) => f.mensaje);
    const envejecer = (id, minutos) => q(`SET session_replication_role = replica;
      UPDATE tpedidos SET fdesde = fdesde - interval '${Number(minutos)} minutes', fpedido = fpedido - interval '${Number(minutos)} minutes' WHERE cpedido = ${Number(id)};
      UPDATE tpedidocomprobantes SET frevision = frevision - interval '${Number(minutos)} minutes' WHERE cpedido = ${Number(id)};
      SET session_replication_role = origin;`);

    seccion('1. Preparación');
    const luis = await t.registrar('luis@test.com', 'Luis', 'Mora', 'vendedor', { nombreNegocio: 'Pizzería Luis' });
    const L = luis.token;
    await api('PUT', '/api/mi-negocio/local', { direccion: 'Av. Amazonas', latitud: -0.18, longitud: -78.48 }, L);
    await api('PATCH', '/api/mi-negocio/estado', { abierto: true }, L);
    const pizza = (await api('POST', '/api/mi-negocio/productos', { nombre: 'Pizza', precio: 10, controlaStock: true, stock: 20 }, L)).body.producto;
    const carlos = await t.registrar('carlos@test.com', 'Carlos', 'Ruiz', 'cliente');
    const C = carlos.token;
    const dir = (await api('POST', '/api/direcciones', { direccion: 'Calle 1', latitud: -0.19, longitud: -78.49, tipo: 'DOM' }, C)).body.direccion;
    const maria = await t.registrar('maria@test.com', 'María', 'León', 'cliente');
    const pedido = { negocioId: pizza.negocioId, direccionId: dir.id, metodoPago: 'transferencia', productos: [{ productoId: pizza.id, cantidad: 1 }] };
    const pedir = async () => (await api('POST', '/api/pedidos', pedido, C)).body.pedido;
    const confirmar = (id) => api('PATCH', `/api/mi-negocio/pedidos/${id}/estado`, { estado: 'confirmado' }, L);
    const foto = await t.imagen(300, 500);
    check('negocio, producto y cliente listos', !!pizza?.id && !!dir?.id);

    seccion('2. Cuentas del negocio');
    let r = await api('GET', `/api/negocios/${pizza.negocioId}`, null, C);
    check('sin cuentas: el negocio no acepta transferencia', r.status === 200 && r.body.negocio.aceptaTransferencia === false, JSON.stringify(r.body.negocio?.aceptaTransferencia));
    r = await api('POST', '/api/pedidos', pedido, C);
    check('pedir por transferencia sin cuentas: 400 TRANSFERENCIANODISPONIBLE', r.status === 400 && r.body.code === 'TRANSFERENCIANODISPONIBLE', JSON.stringify(r.body));
    r = await api('PUT', '/api/mi-negocio/cuentas', { cuentas: [{ banco: 'Pichincha', numero: '2200', titular: '' }] }, L);
    check('cuenta sin titular: 400 CUENTAINCOMPLETA', r.status === 400 && r.body.code === 'CUENTAINCOMPLETA');
    r = await api('PUT', '/api/mi-negocio/cuentas', { cuentas: [{ banco: 'Pichincha', numero: '22-00 ab', titular: 'Luis Mora' }] }, L);
    check('número con letras: 400 CUENTAINVALIDA', r.status === 400 && r.body.code === 'CUENTAINVALIDA');
    r = await api('PUT', '/api/mi-negocio/cuentas', { cuentas: [{ banco: 'Pichincha', numero: '2200', titular: 'Luis Mora', identificacion: '123' }] }, L);
    check('cédula del titular inválida: 400', r.status === 400 && r.body.code === 'CUENTAINVALIDA');
    r = await api('PUT', '/api/mi-negocio/cuentas', { cuentas: Array.from({ length: 6 }, (_, i) => ({ banco: `B${i}`, numero: `1000${i}`, titular: 'Luis' })) }, L);
    check('más de 5 cuentas: 400', r.status === 400);
    r = await api('PUT', '/api/mi-negocio/cuentas', {
      cuentas: [
        { banco: 'Banco Pichincha', tipo: 'ahorros', numero: '2200 1234 56', titular: 'Luis Mora', identificacion: '1900000001' },
        { banco: 'Cooperativa JEP', tipo: 'corriente', numero: '4455667788', titular: 'Luis Mora' },
      ],
    }, L);
    check('guarda dos cuentas (el número sin espacios) en orden', r.status === 200 && r.body.cuentas.length === 2 && r.body.cuentas[0].numero === '2200123456' && r.body.cuentas[1].tipo === 'corriente', JSON.stringify(r.body));
    check('...y las devuelve al consultarlas', (await api('GET', '/api/mi-negocio/cuentas', null, L)).body.cuentas.map((c) => c.banco).join() === 'Banco Pichincha,Cooperativa JEP');
    r = await api('GET', '/api/mi-negocio/cuentas', null, C);
    check('un cliente no ve /mi-negocio/cuentas: 403', r.status === 403);
    r = await api('GET', `/api/negocios/${pizza.negocioId}`, null, C);
    check('ahora el negocio acepta transferencia', r.body.negocio.aceptaTransferencia === true);

    seccion('3. Pedido pendiente: todavía no se paga');
    const p1 = await pedir();
    check('pedido por transferencia creado (pendiente)', p1?.estado === 'pendiente' && p1.metodoPago === 'transferencia' && p1.pagado === false, JSON.stringify(p1));
    check('pendiente: sin cuentas a la vista ni comprobante', p1.transferencia && p1.transferencia.cuentas.length === 0 && p1.transferencia.puedeSubir === false && p1.transferencia.comprobante === null, JSON.stringify(p1.transferencia));
    r = await api('POST', `/api/pedidos/${p1.id}/comprobante`, { imagen: foto }, C);
    check('subir comprobante antes de que confirme: 409 PEDIDONOCONFIRMADO', r.status === 409 && r.body.code === 'PEDIDONOCONFIRMADO');

    seccion('4. Confirmado: el cliente ve las cuentas y paga');
    r = await confirmar(p1.id);
    check('el negocio confirma sin pago (es aceptar el pedido)', r.status === 200 && r.body.pedido.estado === 'confirmado');
    check('el aviso al cliente le pide transferir y subir el comprobante', (await avisos(carlos.usuario.id, 'pedido_confirmado', p1.id))[0]?.includes('Transfiere'));
    check('el negocio no recibe las cuentas en el pedido (son suyas)', r.body.pedido.transferencia?.cuentas.length === 0);
    r = await api('PATCH', `/api/mi-negocio/pedidos/${p1.id}/estado`, { estado: 'preparando' }, L);
    check('preparar sin pago: 409 PAGOPENDIENTE', r.status === 409 && r.body.code === 'PAGOPENDIENTE');
    r = await api('PATCH', `/api/mi-negocio/pedidos/${p1.id}/estado`, { estado: 'listo' }, L);
    check('dejar listo sin pago: 409 PAGOPENDIENTE', r.status === 409 && r.body.code === 'PAGOPENDIENTE');
    r = await api('GET', `/api/pedidos/${p1.id}`, null, C);
    check('el cliente ve las dos cuentas y puede subir', r.body.pedido.transferencia.cuentas.length === 2 && r.body.pedido.transferencia.puedeSubir === true, JSON.stringify(r.body.pedido.transferencia));
    r = await api('POST', `/api/mi-negocio/pedidos/${p1.id}/pago`, { recibido: true }, L);
    check('confirmar el pago sin comprobante: 409 SINCOMPROBANTE', r.status === 409 && r.body.code === 'SINCOMPROBANTE');
    r = await api('POST', `/api/pedidos/${p1.id}/comprobante`, { imagen: foto }, maria.token);
    check('otra persona no sube comprobantes a este pedido: 404', r.status === 404);
    r = await api('POST', `/api/pedidos/${p1.id}/comprobante`, { referencia: '123' }, C);
    check('sin foto: 400', r.status === 400);
    r = await api('POST', `/api/pedidos/${p1.id}/comprobante`, { imagen: foto, referencia: ' 987654 ' }, C);
    const comp1 = r.body.pedido?.transferencia?.comprobante;
    check('sube el comprobante: queda enviado, con su foto y referencia', r.status === 201 && comp1?.estado === 'enviado' && !!comp1.imagen && comp1.referencia === '987654', JSON.stringify(r.body));
    check('...y ya no puede subir otro ni ve las cuentas', r.body.pedido.transferencia.puedeSubir === false && r.body.pedido.transferencia.cuentas.length === 0);
    check('el negocio recibe el aviso de revisar la transferencia', (await avisos(luis.usuario.id, 'pedido_comprobante', p1.id)).length === 1);
    r = await api('POST', `/api/pedidos/${p1.id}/comprobante`, { imagen: foto }, C);
    check('otro comprobante mientras revisa: 409 COMPROBANTEENREVISION', r.status === 409 && r.body.code === 'COMPROBANTEENREVISION');
    r = await api('PATCH', `/api/pedidos/${p1.id}/cancelar`, {}, C);
    check('con el comprobante enviado el cliente ya no cancela: 409', r.status === 409 && r.body.code === 'PEDIDOENPROCESO');
    r = await api('PATCH', `/api/mi-negocio/pedidos/${p1.id}/estado`, { estado: 'rechazado', motivo: 'x' }, L);
    check('con el comprobante enviado el negocio no rechaza: 409 COMPROBANTEPORREVISAR', r.status === 409 && r.body.code === 'COMPROBANTEPORREVISAR');
    r = await api('GET', `/api/mi-negocio/pedidos?estado=activos`, null, L);
    check('el negocio ve el comprobante en su lista', r.body.pedidos.find((x) => x.id === p1.id)?.transferencia?.comprobante?.estado === 'enviado');

    seccion('5. "No me llegó" y nuevo comprobante');
    r = await api('POST', `/api/mi-negocio/pedidos/${p1.id}/pago`, { recibido: false }, L);
    check('rechazar sin motivo: 400', r.status === 400);
    r = await api('POST', `/api/mi-negocio/pedidos/${p1.id}/pago`, { recibido: false, motivo: 'El monto no coincide' }, L);
    check('"No me llegó": el comprobante queda rechazado con el motivo', r.status === 200 && r.body.pedido.transferencia.comprobante.estado === 'rechazado' && r.body.pedido.transferencia.comprobante.motivo === 'El monto no coincide', JSON.stringify(r.body));
    check('el cliente recibe el aviso con el motivo', (await avisos(carlos.usuario.id, 'pago_rechazado', p1.id))[0]?.includes('El monto no coincide'));
    r = await api('GET', `/api/pedidos/${p1.id}`, null, C);
    check('el cliente vuelve a ver las cuentas y puede subir otro', r.body.pedido.transferencia.puedeSubir === true && r.body.pedido.transferencia.cuentas.length === 2);
    r = await api('POST', `/api/pedidos/${p1.id}/comprobante`, { imagen: await t.imagen(310, 500) }, C);
    check('sube el nuevo comprobante', r.status === 201 && r.body.pedido.transferencia.comprobante.estado === 'enviado');

    seccion('6. "Pago recibido"');
    r = await api('POST', `/api/mi-negocio/pedidos/${p1.id}/pago`, { recibido: true }, maria.token);
    check('un cliente no confirma pagos: 403', r.status === 403);
    r = await api('POST', `/api/mi-negocio/pedidos/${p1.id}/pago`, { recibido: true }, L);
    check('"Pago recibido": el pedido queda pagado', r.status === 200 && r.body.pedido.pagado === true && r.body.pedido.transferencia.comprobante.estado === 'aprobado', JSON.stringify(r.body));
    check('el cliente recibe "Pago recibido"', (await avisos(carlos.usuario.id, 'pago_recibido', p1.id)).length === 1);
    r = await api('POST', `/api/mi-negocio/pedidos/${p1.id}/pago`, { recibido: true }, L);
    check('confirmarlo dos veces: 409 YAPAGADO', r.status === 409 && r.body.code === 'YAPAGADO');
    r = await api('PATCH', `/api/mi-negocio/pedidos/${p1.id}/estado`, { estado: 'preparando' }, L);
    check('ya pagado, el negocio lo prepara', r.status === 200 && r.body.pedido.estado === 'preparando');
    check('quedan 2 comprobantes guardados (rechazado y aprobado)', (await q('SELECT estado FROM tpedidocomprobantes WHERE cpedido=$1 ORDER BY ccomprobante', [p1.id])).map((x) => x.estado).join() === 'RECHAZADO,APROBADO');

    seccion('7. Confirmado y sin pago: rechazar o cancelar');
    const p2 = await pedir();
    await confirmar(p2.id);
    r = await api('PATCH', `/api/mi-negocio/pedidos/${p2.id}/estado`, { estado: 'rechazado', motivo: 'El cliente no transfirió' }, L);
    check('el negocio rechaza un confirmado sin pago', r.status === 200 && r.body.pedido.estado === 'rechazado');
    const p3 = await pedir();
    await confirmar(p3.id);
    r = await api('PATCH', `/api/pedidos/${p3.id}/cancelar`, { motivo: 'Me arrepentí' }, C);
    check('el cliente cancela un confirmado que aún no pagó', r.status === 200 && r.body.pedido.estado === 'cancelado');
    const efectivo = (await api('POST', '/api/pedidos', { ...pedido, metodoPago: 'efectivo' }, C)).body.pedido;
    await confirmar(efectivo.id);
    r = await api('PATCH', `/api/mi-negocio/pedidos/${efectivo.id}/estado`, { estado: 'rechazado', motivo: 'x' }, L);
    check('en efectivo, un confirmado no se rechaza (como siempre)', r.status === 409 && r.body.code === 'TRANSICIONINVALIDA');
    r = await api('PATCH', `/api/pedidos/${efectivo.id}/cancelar`, {}, C);
    check('...ni lo cancela el cliente', r.status === 409 && r.body.code === 'PEDIDOENPROCESO');
    check('un pedido en efectivo no trae datos de transferencia', efectivo.transferencia === undefined);
    r = await api('POST', `/api/pedidos/${efectivo.id}/comprobante`, { imagen: foto }, C);
    check('comprobante a un pedido en efectivo: 400 NOESTRANSFERENCIA', r.status === 400 && r.body.code === 'NOESTRANSFERENCIA');

    seccion('8. El vigilante cancela si no llega el comprobante');
    const p4 = await pedir();
    await confirmar(p4.id);
    await dormir(1200);
    check('recién confirmado: no se toca', (await estado(p4.id)).e === '002');
    await envejecer(p4.id, 31);
    await dormir(1200);
    const e4 = await estado(p4.id);
    check('a los 31 min sin comprobante: cancelado', e4.e === '010' && /comprobante/.test(e4.m), JSON.stringify(e4));
    const p5 = await pedir();
    await confirmar(p5.id);
    await api('POST', `/api/pedidos/${p5.id}/comprobante`, { imagen: await t.imagen(320, 500) }, C);
    await envejecer(p5.id, 120);
    await dormir(1200);
    check('con el comprobante en revisión no se cancela aunque pase el tiempo', (await estado(p5.id)).e === '002');
    await api('POST', `/api/mi-negocio/pedidos/${p5.id}/pago`, { recibido: false, motivo: 'No llegó nada' }, L);
    await dormir(1200);
    check('recién rechazado el comprobante: tiene tiempo para subir otro', (await estado(p5.id)).e === '002');
    await envejecer(p5.id, 31);
    await dormir(1200);
    check('31 min después del rechazo sin otro comprobante: cancelado', (await estado(p5.id)).e === '010');
    const aviso5 = (await avisos(luis.usuario.id, 'pedido_cancelado', p5.id))[0] || '';
    check('el comprobante había sido rechazado: no se le pide al negocio devolver nada', aviso5.includes('comprobante') && !aviso5.includes('devuélvele'), aviso5);

    seccion('9. Cancelación por el admin de un pedido pagado');
    const p6 = await pedir();
    await confirmar(p6.id);
    await api('POST', `/api/pedidos/${p6.id}/comprobante`, { imagen: await t.imagen(330, 500) }, C);
    await api('POST', `/api/mi-negocio/pedidos/${p6.id}/pago`, { recibido: true }, L);
    spawnSync(process.execPath, ['scripts/clave-admin.js'], { cwd: path.resolve(__dirname, '..'), env: { ...process.env, DB_NAME: BD, CLAVE: 'admin-secreta-1' }, encoding: 'utf8' });
    const A = (await api('POST', '/api/auth/login', { email: 'admin', password: 'admin-secreta-1' })).body?.token;
    r = await api('GET', `/api/pedidos/${p6.id}`, null, A);
    check('el admin ve el comprobante aprobado del pedido', r.status === 200 && r.body.pedido.transferencia?.comprobante?.estado === 'aprobado', JSON.stringify(r.body).slice(0, 300));
    r = await api('PATCH', `/api/admin/pedidos/${p6.id}/cancelar`, { motivo: 'El negocio cerró' }, A);
    check('el admin cancela un pedido pagado', r.status === 200, JSON.stringify(r.body));
    check('el cliente sabe que el negocio le devuelve lo transferido', (await avisos(carlos.usuario.id, 'pedido_cancelado', p6.id))[0]?.includes('devolverá'));
    r = await api('PUT', `/api/admin/negocios/${pizza.negocioId}/gestion/cuentas`, { cuentas: [{ banco: 'Banco Guayaquil', numero: '99887766', titular: 'Luis Mora' }] }, A);
    check('el admin puede corregir las cuentas del negocio (gestión)', r.status === 200 && r.body.cuentas.length === 1, JSON.stringify(r.body));

    seccion('10. Eliminar la cuenta del vendedor borra sus cuentas bancarias');
    const ana = await t.registrar('ana@test.com', 'Ana', 'Paz', 'vendedor', { nombreNegocio: 'Panadería Ana' });
    await api('PUT', '/api/mi-negocio/cuentas', { cuentas: [{ banco: 'Pichincha', numero: '11112222', titular: 'Ana Paz', identificacion: '1900000002' }] }, ana.token);
    const negAna = (await api('GET', '/api/mi-negocio', null, ana.token)).body.negocio.id;
    check('antes: 1 cuenta', (await q('SELECT 1 FROM tnegociocuentas WHERE cnegocio=$1', [negAna])).length === 1);
    r = await api('POST', '/api/auth/eliminar-cuenta', { password: 'secreto1' }, ana.token);
    check('elimina su cuenta y sus cuentas bancarias desaparecen', r.status === 200 && (await q('SELECT 1 FROM tnegociocuentas WHERE cnegocio=$1', [negAna])).length === 0, JSON.stringify(r.body));
  } catch (e) {
    return t.finalizar(e);
  }
  return t.finalizar();
})();
