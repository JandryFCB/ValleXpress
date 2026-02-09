-- ===============================
-- ValleXpress - Clean Schema (PostgreSQL 15)
-- 11 tablas - listo para init.sql / schema.sql
-- ===============================

-- Extensiones
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ===============================
-- ENUMS (idempotente)
-- ===============================
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'enum_usuarios_tipo_usuario') THEN
    CREATE TYPE enum_usuarios_tipo_usuario AS ENUM ('cliente', 'vendedor', 'repartidor');
  END IF;
END $$;

-- ===============================
-- TABLAS
-- ===============================

CREATE TABLE IF NOT EXISTS public.usuarios (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  nombre varchar(100) NOT NULL,
  apellido varchar(100) NOT NULL,
  email varchar(150) NOT NULL UNIQUE,
  telefono varchar(20),
  password_hash varchar(255) NOT NULL,
  tipo_usuario enum_usuarios_tipo_usuario NOT NULL,
  foto_perfil text,
  activo boolean DEFAULT true,
  verificado boolean DEFAULT false,
  fecha_registro timestamptz,
  ultima_conexion timestamptz,
  created_at timestamptz NOT NULL,
  updated_at timestamptz NOT NULL,
  cedula varchar(10) NOT NULL UNIQUE
);

CREATE INDEX IF NOT EXISTS idx_usuarios_email ON public.usuarios(email);
CREATE INDEX IF NOT EXISTS idx_usuarios_tipo_usuario ON public.usuarios(tipo_usuario);

-- --------------------------------

CREATE TABLE IF NOT EXISTS public.direcciones (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  usuario_id uuid REFERENCES public.usuarios(id) ON DELETE CASCADE,
  nombre varchar(50),
  direccion text NOT NULL,
  latitud numeric(10,8) NOT NULL,
  longitud numeric(11,8) NOT NULL,
  es_predeterminada boolean DEFAULT false,
  created_at timestamp DEFAULT CURRENT_TIMESTAMP,
  updated_at timestamp DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_direcciones_usuario_id ON public.direcciones(usuario_id);

-- --------------------------------

CREATE TABLE IF NOT EXISTS public.vendedores (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  usuario_id uuid NOT NULL REFERENCES public.usuarios(id) ON UPDATE CASCADE,
  nombre_negocio varchar(200) NOT NULL,
  descripcion text,
  logo text,
  banner text,
  categoria varchar(50),
  calificacion_promedio numeric(3,2) DEFAULT 0,
  total_calificaciones integer DEFAULT 0,
  horario_apertura varchar(10),
  horario_cierre varchar(10),
  dias_atencion varchar(100),
  tiempo_preparacion_promedio integer,
  costo_delivery numeric(10,2),
  radio_cobertura integer,
  abierto_ahora boolean DEFAULT false,
  created_at timestamp DEFAULT CURRENT_TIMESTAMP,
  updated_at timestamp DEFAULT CURRENT_TIMESTAMP,
  cedula varchar(10) UNIQUE,
  latitud numeric(10,8),
  longitud numeric(11,8)
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_vendedores_cedula ON public.vendedores(cedula);

-- --------------------------------

CREATE TABLE IF NOT EXISTS public.productos (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  vendedor_id uuid REFERENCES public.vendedores(id) ON DELETE CASCADE,
  nombre varchar(200) NOT NULL,
  descripcion text,
  precio numeric(10,2) NOT NULL,
  imagen text,
  categoria varchar(50),
  disponible boolean DEFAULT true,
  tiempo_preparacion integer,
  stock integer DEFAULT 0,
  created_at timestamp DEFAULT CURRENT_TIMESTAMP,
  updated_at timestamp DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_productos_vendedor_id ON public.productos(vendedor_id);

-- --------------------------------

CREATE TABLE IF NOT EXISTS public.repartidores (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  usuario_id uuid NOT NULL REFERENCES public.usuarios(id) ON UPDATE CASCADE,
  vehiculo varchar(50),
  placa varchar(20),
  licencia varchar(50),
  calificacion_promedio numeric(3,2) DEFAULT 0,
  total_calificaciones integer DEFAULT 0,
  disponible boolean DEFAULT false,
  latitud numeric(10,8),
  longitud numeric(11,8),
  pedidos_completados integer DEFAULT 0,
  created_at timestamptz NOT NULL,
  updated_at timestamptz NOT NULL,
  cedula varchar(10) UNIQUE,
  foto text
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_repartidores_cedula ON public.repartidores(cedula);

-- --------------------------------

CREATE TABLE IF NOT EXISTS public.pedidos (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  numero_pedido varchar(20) NOT NULL UNIQUE,
  cliente_id uuid REFERENCES public.usuarios(id),
  vendedor_id uuid REFERENCES public.vendedores(id),
  repartidor_id uuid REFERENCES public.repartidores(id),
  direccion_entrega_id uuid REFERENCES public.direcciones(id),
  estado varchar(50),
  subtotal numeric(10,2) NOT NULL,
  costo_delivery numeric(10,2) NOT NULL,
  total numeric(10,2) NOT NULL,
  metodo_pago varchar(50),
  pagado boolean DEFAULT false,
  paypal_order_id varchar(100),
  notas_cliente text,
  tiempo_estimado integer,
  fecha_pedido timestamp DEFAULT CURRENT_TIMESTAMP,
  fecha_confirmacion timestamp,
  fecha_preparacion timestamp,
  fecha_listo timestamp,
  fecha_recogida timestamp,
  fecha_entrega timestamp,
  created_at timestamp DEFAULT CURRENT_TIMESTAMP,
  updated_at timestamp DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT pedidos_estado_check CHECK (
    (estado)::text = ANY (
      (ARRAY[
        'pendiente'::character varying,
        'confirmado'::character varying,
        'preparando'::character varying,
        'listo'::character varying,
        'recogido'::character varying,
        'en_camino'::character varying,
        'entregado'::character varying,
        'recibido_cliente'::character varying,
        'cancelado'::character varying
      ])::text[]
    )
  )
);

CREATE INDEX IF NOT EXISTS idx_pedidos_estado ON public.pedidos(estado);
CREATE INDEX IF NOT EXISTS idx_pedidos_cliente_id ON public.pedidos(cliente_id);
CREATE INDEX IF NOT EXISTS idx_pedidos_vendedor_id ON public.pedidos(vendedor_id);
CREATE INDEX IF NOT EXISTS idx_pedidos_repartidor_id ON public.pedidos(repartidor_id);

-- --------------------------------

CREATE TABLE IF NOT EXISTS public.detalle_pedidos (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  pedido_id uuid REFERENCES public.pedidos(id) ON DELETE CASCADE,
  producto_id uuid REFERENCES public.productos(id),
  cantidad integer NOT NULL,
  precio_unitario numeric(10,2) NOT NULL,
  subtotal numeric(10,2) NOT NULL,
  notas text
);

CREATE INDEX IF NOT EXISTS idx_detalle_pedidos_pedido_id ON public.detalle_pedidos(pedido_id);

-- --------------------------------

CREATE TABLE IF NOT EXISTS public.calificaciones (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  pedido_id uuid REFERENCES public.pedidos(id),
  usuario_id uuid REFERENCES public.usuarios(id),
  vendedor_id uuid REFERENCES public.vendedores(id),
  repartidor_id uuid REFERENCES public.repartidores(id),
  puntuacion numeric(2,1) CHECK (puntuacion BETWEEN 1 AND 5),
  comentario text,
  tipo varchar(20) CHECK (tipo IN ('vendedor','repartidor')),
  created_at timestamp DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_calificaciones_pedido_id ON public.calificaciones(pedido_id);
CREATE INDEX IF NOT EXISTS idx_calificaciones_vendedor_id ON public.calificaciones(vendedor_id);
CREATE INDEX IF NOT EXISTS idx_calificaciones_repartidor_id ON public.calificaciones(repartidor_id);

-- --------------------------------

CREATE TABLE IF NOT EXISTS public.notificaciones (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  usuario_id uuid REFERENCES public.usuarios(id) ON DELETE CASCADE,
  titulo varchar(200) NOT NULL,
  mensaje text NOT NULL,
  tipo varchar(50),
  leida boolean DEFAULT false,
  pedido_id uuid REFERENCES public.pedidos(id),
  created_at timestamp DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_notificaciones_usuario_id ON public.notificaciones(usuario_id);
CREATE INDEX IF NOT EXISTS idx_notificaciones_pedido_id ON public.notificaciones(pedido_id);

-- --------------------------------

CREATE TABLE IF NOT EXISTS public.password_reset_codes (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id uuid NULL REFERENCES public.usuarios(id) ON DELETE SET NULL,
  email varchar(200) NOT NULL,
  code_hash varchar(255) NOT NULL,
  expires_at timestamp NOT NULL,
  attempts integer NOT NULL DEFAULT 0,
  used_at timestamp NULL,
  created_at timestamp DEFAULT CURRENT_TIMESTAMP,
  updated_at timestamp DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_reset_email ON public.password_reset_codes(email);

-- --------------------------------

CREATE TABLE IF NOT EXISTS public.device_tokens (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  usuario_id uuid NOT NULL REFERENCES public.usuarios(id) ON DELETE CASCADE,
  token text NOT NULL,
  platform varchar(20),
  created_at timestamptz NOT NULL DEFAULT NOW(),
  updated_at timestamptz NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_device_tokens_usuario_id ON public.device_tokens(usuario_id);
CREATE UNIQUE INDEX IF NOT EXISTS ux_device_tokens_token ON public.device_tokens(token);
