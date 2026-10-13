# Patrón de tablas en FitBank (Gualaquiza)

Análisis basado en los mapeos `.hbm.xml` de `gualaquiza-persistence` (2.675 tablas mapeadas) y en los scripts DDL de `sql/modelo`.

---

## 1. Idea central: tabla `...ID` + tabla histórica

FitBank separa una entidad en dos tablas:

| Tabla | Qué guarda | PK | Ejemplos |
|---|---|---|---|
| **T`<NOMBRE>`ID** | Que la entidad **existe** (su código) | Solo el código | `TPERSONAID (CPERSONA)`, `TUSUARIOSID (CUSUARIO)` |
| **T`<NOMBRE>`** | Los **datos** de la entidad, versionados | Código + `FHASTA` | `TPERSONA (CPERSONA, FHASTA)`, `TUSUARIOS (CUSUARIO, FHASTA)` |

### ¿Por qué dos tablas?
En la tabla histórica, `FHASTA` forma parte de la PK, así que el mismo `CPERSONA` aparece en varias filas (una por versión). **Una FK no puede apuntar a una tabla donde el código se repite.** Por eso la tabla `...ID` existe para tener el código **una sola vez** y que todas las FK apunten a ella.

```
TPERSONAID (CPERSONA)                 TUSUARIOSID (CUSUARIO)
     ▲            ▲                         ▲
     │ FK         │ FK                      │ FK
TPERSONA          └──── TUSUARIOS (CUSUARIO, FHASTA, ..., CPERSONA)
(CPERSONA, FHASTA, ...)
```

- `TPERSONA.CPERSONA` → `TPERSONAID.CPERSONA`
- `TUSUARIOS.CUSUARIO` → `TUSUARIOSID.CUSUARIO`
- `TUSUARIOS.CPERSONA` → `TPERSONAID.CPERSONA` (al ID, **nunca** a `TPERSONA`)

**Orden obligatorio de inserción:**
`TPERSONAID` → `TPERSONA` → `TUSUARIOSID` → `TUSUARIOS`
(y al borrar, en orden inverso).

---

## 2. ¿Cuándo se crea una tabla `ID` y cuándo no?

Cifras del modelo actual:

| Caso | Cantidad |
|---|---|
| Tablas históricas (con `FHASTA`) **con** tabla `ID` | 642 |
| Tablas históricas **sin** tabla `ID` | 867 |
| Tablas `ID` **sin** histórica | 19 |
| Tablas ni históricas ni `ID` (transaccionales, logs) | ~506 |

### ✅ SÍ se crea tabla `ID` cuando…

1. **Otras tablas la van a referenciar con FK.** Es la razón principal. Si el código de la entidad va a aparecer como columna en otras tablas (`CPERSONA`, `CUSUARIO`, `CTIPOUSUARIO`, `CROL`…), necesita una tabla `ID` como destino de la FK.
2. **Es una entidad maestra o un catálogo.** Personas, usuarios, cuentas, productos, roles, tipos, estatus. Ejemplo: `TTIPOSUSUARIOID` / `TTIPOSUSUARIO`, `TROLESID` / `TROLES`.
3. **Tiene datos que nunca cambian.** La tabla `ID` puede llevar columnas propias si son atributos **fijos**, que no necesitan historial:
   - `TTIPOSUSUARIOID`: `CTIPOUSUARIO`, `EXIGEHORARIO`
   - `TROLESID`: `CROL`, `TIEMPOSESION`, `CUSUARIO_INGRESO`, `FINGRESO`
   - `TCOMPANIAUSUARIOSID`: `CPERSONA_COMPANIA`, `CUSUARIO`, `CCODIGOUSUARIO`
4. **Es una relación que a su vez es referenciada.** Ejemplo: `TCUENTASPERSONAID (CPERSONA, CCUENTA, CPERSONA_COMPANIA)` / `TCUENTASPERSONA`.

### ❌ NO se crea tabla `ID` cuando…

1. **Es histórica, pero nadie la referencia.** Es un detalle o hijo de otra entidad: solo guarda datos versionados, y su PK ya apunta a la `ID` del padre.
   - Ejemplos: `TACUERDOPAGOSDETALLE`, `TACTIVOSFIJOSDEPRECIACION`, `TBACKPERSONADIRECCIONES`, `TPERSONAACUMULADOBILLETES` (propia de Gualaquiza).
2. **Es transaccional, de movimiento o de log.** Se inserta una vez y no se versiona: no tiene `FHASTA` ni `ID`. Su PK es un número de mensaje o secuencia.
   - `TMOVIMIENTOS (NUMEROMENSAJE, STRANSACCION, PARTICION)`, `TMOVIMIENTOSCAJA`, `TSALDOSCONTABLESDIARIO`, tablas de facturación electrónica `FEFACTURA*`.
3. **Es de configuración o parametrización simple** que no se versiona ni se referencia: `TATMESTADOS`, `TCAJACALCULADORA`, etc.

### Caso especial: `ID` sin histórica
Son 19 casos (por ejemplo `TSUBCUENTASID`, `TESTATUSCONTABLEID`, `TCANALTRANSACCIONESID`). La entidad se referencia por FK, pero sus datos no necesitan historial: toda su información cabe en la tabla `ID`.

### Regla rápida de decisión

```
¿Otra tabla va a tener una FK hacia esta entidad?
 ├─ SÍ → crear T<NOMBRE>ID
 │        └─ ¿Sus datos cambian y hay que conservar el historial?
 │             ├─ SÍ → además T<NOMBRE> con FHASTA/FDESDE/VERSIONCONTROL
 │             └─ NO → solo T<NOMBRE>ID (con sus columnas fijas)
 └─ NO  → no crear ID
          └─ ¿Sus datos cambian y hay que conservar el historial?
               ├─ SÍ → solo T<NOMBRE> con FHASTA (PK apunta al ID del padre)
               └─ NO → tabla simple (movimientos, logs, parámetros)
```

---

## 3. Manejo del historial

Columnas obligatorias en toda tabla histórica:

| Columna | Tipo | Uso |
|---|---|---|
| `FHASTA` | `TIMESTAMP`, parte de la PK | Fin de vigencia. La fila **vigente** tiene `2999-12-31` |
| `FDESDE` | `TIMESTAMP` not null | Inicio de vigencia |
| `VERSIONCONTROL` | `NUMBER(22) default 0` | Bloqueo optimista (en el `.hbm` se declara con `<version>`) |

Al modificar un registro, la fila vigente se cierra (`FHASTA = ahora`) y se inserta una nueva (`FDESDE = ahora`, `FHASTA = 2999-12-31`). Para leer los datos actuales siempre se filtra `FHASTA = 2999-12-31`.

---

## 4. Variantes del patrón

| Variante | Estructura | Ejemplo |
|---|---|---|
| Catálogo con idioma | ID: `(CCODIGO)` · Histórica: `(CIDIOMA, CCODIGO, FHASTA)` + `DESCRIPCION` | `TTIPOSUSUARIOID` / `TTIPOSUSUARIO` |
| Relación entre entidades | ID y histórica con PK compuesta por los códigos de ambas | `TCUENTASPERSONAID` / `TCUENTASPERSONA` |
| Multiempresa | `CPERSONA_COMPANIA` dentro de la PK | `TCOMPANIAUSUARIOSID`, `TCUENTASPERSONA` |

---

## 5. Convenciones de nombres

### Tablas
- Prefijo `T`, MAYÚSCULAS, en español, **sin `_`**: `TPERSONAACUMULADOBILLETES`, `TCUENTAINVERSIONESCUPONES`.
- La tabla `ID` usa **exactamente** el mismo nombre que la histórica, más `ID`: `TUSUARIOS` → `TUSUARIOSID`.

### Columnas: el prefijo indica el tipo

| Prefijo | Significado | Ejemplos |
|---|---|---|
| `C` | Código o clave | `CPERSONA`, `CUSUARIO`, `CTIPOUSUARIO`, `CESTATUSUSUARIO` |
| `F` | Fecha | `FHASTA`, `FDESDE`, `FCONTABLE`, `FINGRESO` |
| `S` | Secuencia | `STRANSACCION`, `SPERSONASERVICIOCONTRATO` |
| `ES` / `PERMITE` / `EXIGE` | Bandera `0`/`1` (`VARCHAR2(1)`) | `ESCAJERO`, `ESOFICIAL`, `PERMITECAMBIO`, `EXIGEHORARIO` |
| `NUMERO` | Número o cantidad | `NUMERODIRECCION`, `NUMEROCUPON` |
| sin prefijo | Valor descriptivo | `NOMBRELEGAL`, `OBSERVACIONES`, `TASA` |

**Regla de FK:** la columna se llama **igual** que la PK a la que apunta y tiene el **mismo tipo y longitud** (`CPERSONA` → `TPERSONAID.CPERSONA`).

**Uso del `_`:** solo para indicar el **rol** cuando una tabla tiene varias referencias a la misma PK o cuando el nombre base sería ambiguo:
`CPERSONA_COMPANIA`, `CPERSONA_CLIENTE`, `CPERSONA_EMISOR`, `CUSUARIO_MODIFICACION`, `CNIVELMENU_PADRE`.
El resto de las columnas no lleva `_`.

### Constraints
- PK: `IPK<abreviatura>` → `IPKCTAINVCUPON`
- FK: `FK<abrevOrigen><abrevDestino>` → `FKCTAINVPEREMI` (cuenta inversión → persona emisor)
- Máximo 30 caracteres (Oracle 10g), por eso se abrevia.
- Cada tabla y cada columna lleva su `comment on table/column`.

### Persistencia Java (Hibernate)
- Clase con el nombre en inglés: `TPERSONAID` → `Tpersonid`, `TUSUARIOS` → `Tuser`.
- PK simple (tablas `ID`): `<id ...><generator class='assigned'/></id>`.
- PK compuesta: clase adicional `<Clase>Key` + `<composite-id>` en el `.hbm.xml`.
- Cada columna lleva en el `.hbm.xml` un comentario `<!-- DESCRIPCION -->`.

---

## 6. Checklist antes de diseñar una tabla

1. ¿Otras tablas la referenciarán? → tabla `ID`.
2. ¿Sus datos cambian y hay que conservar el historial? → `FHASTA` (en PK) + `FDESDE` + `VERSIONCONTROL`.
3. ¿Tiene textos visibles al usuario (catálogo)? → `CIDIOMA` en la PK de la histórica.
4. ¿Depende de la cooperativa? → `CPERSONA_COMPANIA` en la PK.
5. ¿Es un movimiento o log que no se modifica? → tabla simple, PK por secuencia o mensaje.
6. ¿Las columnas FK tienen el mismo nombre, tipo y longitud que la PK destino, y todas apuntan a tablas `...ID`?
7. ¿Nombres sin `_`, salvo los roles de FK?
