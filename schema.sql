CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS clientes (
    id_cliente          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    nombre_comercial    VARCHAR(150) NOT NULL,
    razon_social        VARCHAR(200) NOT NULL,
    nit_documento       VARCHAR(30)  NOT NULL UNIQUE,
    email               VARCHAR(150) NOT NULL UNIQUE,
    usuario             VARCHAR(80)  NOT NULL UNIQUE,
    contrasena          VARCHAR(255) NOT NULL,
    telefono            VARCHAR(20),
    estado              VARCHAR(30)  NOT NULL DEFAULT 'activo'
        CHECK (estado IN ('pendiente_de_validacion', 'activo', 'inactivo', 'bloqueado')),
    fecha_registro      TIMESTAMPTZ  NOT NULL DEFAULT now(),
    rol                 VARCHAR(20)  NOT NULL DEFAULT 'CLIENTE'
        CHECK (rol IN ('CLIENTE', 'ADMINISTRADOR')),
    actualizado_por     UUID,
    fecha_actualizacion TIMESTAMPTZ,
    motivo              VARCHAR(200),
    intentos_fallidos   INTEGER      NOT NULL DEFAULT 0,
    bloqueado_hasta     TIMESTAMPTZ,
    CONSTRAINT fk_clientes_actualizado_por
        FOREIGN KEY (actualizado_por) REFERENCES clientes (id_cliente)
);

CREATE TABLE IF NOT EXISTS cuentas (
    id_cuenta               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    id_cliente              UUID           NOT NULL REFERENCES clientes (id_cliente),
    numero_cuenta            VARCHAR(20)    NOT NULL UNIQUE,
    estado                   VARCHAR(30)    NOT NULL DEFAULT 'activo'
        CHECK (estado IN ('activo', 'inactivo', 'bloqueado')),
    saldo                    NUMERIC(19, 2) NOT NULL DEFAULT 0
        CHECK (saldo >= 0),
    motivo                   VARCHAR(200),
    operaciones_suspendidas  BOOLEAN        NOT NULL DEFAULT FALSE,
    fecha_vinculacion        TIMESTAMPTZ    NOT NULL DEFAULT now(),
    fecha_actualizacion      TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_cuentas_cliente_estado ON cuentas (id_cliente, estado);

CREATE TABLE IF NOT EXISTS credenciales_api (
    id_credencial    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    id_cliente       UUID NOT NULL REFERENCES clientes(id_cliente) ON DELETE CASCADE,
    api_key          VARCHAR(64) NOT NULL UNIQUE,
    api_secret_hash  VARCHAR(255) NOT NULL,
    ambiente         VARCHAR(20) NOT NULL DEFAULT 'test'
        CHECK (ambiente IN ('test', 'produccion')),
    estado           VARCHAR(20) NOT NULL DEFAULT 'activa'
        CHECK (estado IN ('activa', 'revocada', 'expirada')),
    fecha_creacion   TIMESTAMPTZ NOT NULL DEFAULT now(),
    fecha_expiracion TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_credenciales_cliente ON credenciales_api(id_cliente);
CREATE INDEX IF NOT EXISTS idx_credenciales_estado ON credenciales_api(estado);

CREATE TABLE IF NOT EXISTS transacciones (
    id_transaccion      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    id_cliente          UUID NOT NULL REFERENCES clientes(id_cliente) ON DELETE RESTRICT,
    id_cuenta_origen    UUID REFERENCES cuentas(id_cuenta) ON DELETE RESTRICT,
    id_cuenta_destino   UUID REFERENCES cuentas(id_cuenta) ON DELETE RESTRICT,
    monto               NUMERIC(14,2) NOT NULL CHECK (monto > 0),
    moneda               CHAR(3) NOT NULL DEFAULT 'COP',
    estado               VARCHAR(20) NOT NULL DEFAULT 'creado'
        CHECK (estado IN ('creado', 'aprobado', 'rechazado', 'reembolsado')),
    referencia_externa   VARCHAR(100) UNIQUE,
    fecha_creacion       TIMESTAMPTZ NOT NULL DEFAULT now(),
    fecha_actualizacion  TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (id_cuenta_origen IS DISTINCT FROM id_cuenta_destino)
);

CREATE INDEX IF NOT EXISTS idx_transacciones_cliente ON transacciones(id_cliente);
CREATE INDEX IF NOT EXISTS idx_transacciones_estado ON transacciones(estado);
CREATE INDEX IF NOT EXISTS idx_transacciones_fecha ON transacciones(fecha_creacion);

CREATE TABLE IF NOT EXISTS eventos_transaccion (
    id_evento        BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_transaccion   UUID NOT NULL REFERENCES transacciones(id_transaccion) ON DELETE CASCADE,
    tipo_evento      VARCHAR(50) NOT NULL,
    estado_anterior  VARCHAR(20),
    estado_nuevo     VARCHAR(20),
    detalle          TEXT,
    fecha_evento     TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_eventos_transaccion ON eventos_transaccion(id_transaccion);
CREATE INDEX IF NOT EXISTS idx_eventos_fecha ON eventos_transaccion(fecha_evento);

CREATE TABLE IF NOT EXISTS reportes (
    id_reporte        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    id_cliente        UUID NOT NULL REFERENCES clientes(id_cliente) ON DELETE CASCADE,
    tipo_reporte      VARCHAR(50) NOT NULL
        CHECK (tipo_reporte IN ('volumen_transacciones', 'actividad_comercio')),
    periodo_inicio    DATE NOT NULL,
    periodo_fin       DATE NOT NULL,
    fecha_generacion  TIMESTAMPTZ NOT NULL DEFAULT now(),
    contenido         JSONB,
    CHECK (periodo_fin >= periodo_inicio)
);

CREATE INDEX IF NOT EXISTS idx_reportes_cliente ON reportes(id_cliente);
