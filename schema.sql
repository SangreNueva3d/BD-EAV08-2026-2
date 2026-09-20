-- ENTREGABLES SPRINT 1 EAV08 BD 
-- Modelo físico (schema.sql)
-- PostgreSQL

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ------------------------------------------------------------
-- tabla clientes, comercios o personas 
-- ------------------------------------------------------------
CREATE TABLE clientes (
    id_cliente       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    nombre_comercial VARCHAR(150) NOT NULL,
    razon_social     VARCHAR(200) NOT NULL,
    nit_documento    VARCHAR(30)  NOT NULL UNIQUE,
    email            VARCHAR(150) NOT NULL UNIQUE,
    telefono         VARCHAR(20),
    estado           VARCHAR(20)  NOT NULL DEFAULT 'activo'
                      CHECK (estado IN ('activo', 'inactivo', 'suspendido')),
    fecha_registro   TIMESTAMPTZ  NOT NULL DEFAULT now()
);

-- ------------------------------------------------------------
-- tabla cuentas bancarias, hace referencia a un cliente o comercio
-- ------------------------------------------------------------
CREATE TABLE cuentas_bancarias (
    id_cuenta         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    id_cliente        UUID NOT NULL REFERENCES clientes(id_cliente) ON DELETE RESTRICT,
    numero_cuenta     VARCHAR(34) NOT NULL,
    banco             VARCHAR(100) NOT NULL,
    tipo_cuenta       VARCHAR(20) NOT NULL
                       CHECK (tipo_cuenta IN ('ahorros', 'corriente')),
    moneda            CHAR(3) NOT NULL DEFAULT 'COP',
    estado            VARCHAR(20) NOT NULL DEFAULT 'activa'
                       CHECK (estado IN ('activa', 'inactiva')),
    fecha_vinculacion TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (banco, numero_cuenta)
);

CREATE INDEX idx_cuentas_cliente ON cuentas_bancarias(id_cliente);

-- ------------------------------------------------------------
-- tabla credenciales_api, llaves de un cliente para acceso a la api
-- ------------------------------------------------------------
CREATE TABLE credenciales_api (
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

CREATE INDEX idx_credenciales_cliente ON credenciales_api(id_cliente);
CREATE INDEX idx_credenciales_estado ON credenciales_api(estado);

-- ------------------------------------------------------------
-- tabla transacciones, transacciones entre cuentas atravez de la api
-- ------------------------------------------------------------
CREATE TABLE transacciones (
    id_transaccion      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    id_cliente          UUID NOT NULL REFERENCES clientes(id_cliente) ON DELETE RESTRICT,
    id_cuenta_origen    UUID REFERENCES cuentas_bancarias(id_cuenta) ON DELETE RESTRICT,
    id_cuenta_destino   UUID REFERENCES cuentas_bancarias(id_cuenta) ON DELETE RESTRICT,
    monto               NUMERIC(14,2) NOT NULL CHECK (monto > 0),
    moneda               CHAR(3) NOT NULL DEFAULT 'COP',
    estado               VARCHAR(20) NOT NULL DEFAULT 'creado'
                          CHECK (estado IN ('creado', 'aprobado', 'rechazado', 'reembolsado')),
    referencia_externa   VARCHAR(100) UNIQUE,
    fecha_creacion       TIMESTAMPTZ NOT NULL DEFAULT now(),
    fecha_actualizacion  TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (id_cuenta_origen IS DISTINCT FROM id_cuenta_destino)
);

CREATE INDEX idx_transacciones_cliente ON transacciones(id_cliente);
CREATE INDEX idx_transacciones_estado ON transacciones(estado);
CREATE INDEX idx_transacciones_fecha ON transacciones(fecha_creacion);

-- ------------------------------------------------------------
-- tabla eventos_transsaccion, bitacora de transacciones para auditoria
-- ------------------------------------------------------------
CREATE TABLE eventos_transaccion (
    id_evento        BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_transaccion   UUID NOT NULL REFERENCES transacciones(id_transaccion) ON DELETE CASCADE,
    tipo_evento      VARCHAR(50) NOT NULL,
    estado_anterior  VARCHAR(20),
    estado_nuevo     VARCHAR(20),
    detalle          TEXT,
    fecha_evento     TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_eventos_transaccion ON eventos_transaccion(id_transaccion);
CREATE INDEX idx_eventos_fecha ON eventos_transaccion(fecha_evento);

-- ------------------------------------------------------------
-- tabla reportes, reportes por volumen y actividad por clientes
-- ------------------------------------------------------------
CREATE TABLE reportes (
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

CREATE INDEX idx_reportes_cliente ON reportes(id_cliente);
