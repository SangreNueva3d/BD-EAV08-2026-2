-- ============================================================================
-- Esquema de BackendBank para PostgreSQL / Supabase (Sprint 3)
-- Idempotente para ejecución en arranque de Spring Boot y bases vacías.
-- ============================================================================

CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ============================================================================
-- 1. ESTRUCTURAS DE TABLAS E ÍNDICES
-- ============================================================================

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

ALTER TABLE clientes ADD COLUMN IF NOT EXISTS bloqueado_hasta TIMESTAMPTZ;

CREATE TABLE IF NOT EXISTS cuentas (
    id_cuenta               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    id_cliente              UUID           NOT NULL REFERENCES clientes (id_cliente),
    numero_cuenta           VARCHAR(20)    NOT NULL UNIQUE,
    estado                  VARCHAR(30)    NOT NULL DEFAULT 'activo'
        CHECK (estado IN ('activo', 'inactivo', 'bloqueado')),
    saldo                   NUMERIC(19, 2) NOT NULL DEFAULT 0
        CHECK (saldo >= 0),
    motivo                  VARCHAR(200),
    operaciones_suspendidas BOOLEAN        NOT NULL DEFAULT FALSE,
    fecha_vinculacion       TIMESTAMPTZ    NOT NULL DEFAULT now(),
    fecha_actualizacion     TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_cuentas_cliente_estado
    ON cuentas (id_cliente, estado);

CREATE TABLE IF NOT EXISTS transacciones (
    id_transaccion      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    id_cliente          UUID           NOT NULL REFERENCES clientes (id_cliente) ON DELETE RESTRICT,
    id_cuenta_origen    UUID           REFERENCES cuentas (id_cuenta) ON DELETE RESTRICT,
    id_cuenta_destino   UUID           REFERENCES cuentas (id_cuenta) ON DELETE RESTRICT,
    monto               NUMERIC(14, 2) NOT NULL CHECK (monto > 0),
    moneda              CHAR(3)        NOT NULL DEFAULT 'COP',
    estado              VARCHAR(20)    NOT NULL DEFAULT 'creado'
        CHECK (estado IN ('creado', 'aprobado', 'rechazado', 'reembolsado')),
    referencia_externa  VARCHAR(100)   UNIQUE,
    fecha_creacion      TIMESTAMPTZ    NOT NULL DEFAULT now(),
    fecha_actualizacion TIMESTAMPTZ    NOT NULL DEFAULT now(),
    CHECK (id_cuenta_origen IS DISTINCT FROM id_cuenta_destino)
);

CREATE INDEX IF NOT EXISTS idx_transacciones_cliente ON transacciones (id_cliente);
CREATE INDEX IF NOT EXISTS idx_transacciones_estado ON transacciones (estado);
CREATE INDEX IF NOT EXISTS idx_transacciones_fecha ON transacciones (fecha_creacion);
CREATE INDEX IF NOT EXISTS idx_transacciones_destino ON transacciones (id_cuenta_destino);
CREATE INDEX IF NOT EXISTS idx_transacciones_origen ON transacciones (id_cuenta_origen);

CREATE TABLE IF NOT EXISTS eventos_transaccion (
    id_evento        BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_transaccion   UUID        NOT NULL REFERENCES transacciones (id_transaccion) ON DELETE CASCADE,
    tipo_evento      VARCHAR(50) NOT NULL,
    estado_anterior  VARCHAR(20),
    estado_nuevo     VARCHAR(20),
    detalle          TEXT,
    fecha_evento     TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_eventos_transaccion_id
    ON eventos_transaccion (id_transaccion, fecha_evento);

CREATE TABLE IF NOT EXISTS retiros (
    id_retiro   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    id_cliente  UUID           NOT NULL REFERENCES clientes (id_cliente),
    id_cuenta   UUID           NOT NULL REFERENCES cuentas (id_cuenta),
    monto       NUMERIC(14, 2) NOT NULL CHECK (monto > 0),
    fecha       TIMESTAMPTZ    NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_retiros_cuenta ON retiros (id_cuenta, fecha);
CREATE INDEX IF NOT EXISTS idx_retiros_cliente ON retiros (id_cliente, fecha);

-- ============================================================================
-- 2. FUNCIONES DE TRIGGER Y TRIGGERS (CRITERIO 3)
-- ============================================================================

-- Trigger 1: Validar titularidad, estado activo y monto > 0 en retiros
-- Atiende HU: Retirar dinero solo desde una cuenta propia / Retirar dinero de una cuenta propia / Aceptar solo un monto de retiro mayor que cero
CREATE OR REPLACE FUNCTION fn_validar_retiro()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_propietario UUID;
    v_estado_cuenta VARCHAR(30);
    v_suspendida BOOLEAN;
BEGIN
    IF NEW.monto IS NULL OR NEW.monto <= 0 THEN
        RAISE EXCEPTION 'El monto de retiro debe ser mayor que cero';
    END IF;

    SELECT id_cliente, estado, operaciones_suspendidas
      INTO v_propietario, v_estado_cuenta, v_suspendida
      FROM cuentas
     WHERE id_cuenta = NEW.id_cuenta;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'La cuenta financiera indicada no existe';
    END IF;

    IF v_propietario <> NEW.id_cliente THEN
        RAISE EXCEPTION 'Solo puede retirar dinero desde una cuenta propia';
    END IF;

    IF v_estado_cuenta <> 'activo' OR v_suspendida IS TRUE THEN
        RAISE EXCEPTION 'La cuenta no se encuentra habilitada para operar (estado: %)', v_estado_cuenta;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_validar_retiro ON retiros;
CREATE TRIGGER trg_validar_retiro
    BEFORE INSERT ON retiros
    FOR EACH ROW
    EXECUTE FUNCTION fn_validar_retiro();

-- Trigger 2: Validar reglas de depósitos, retiros y transferencias en transacciones
-- Atiende HU: Depositar dinero en una cuenta del banco / Enviar dinero solo desde una cuenta propia / Impedir transferencia a la misma cuenta / Monto > 0
CREATE OR REPLACE FUNCTION fn_validar_transaccion()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_propietario_origen UUID;
    v_estado_origen VARCHAR(30);
    v_suspendida_origen BOOLEAN;
    v_estado_destino VARCHAR(30);
    v_suspendida_destino BOOLEAN;
BEGIN
    IF NEW.monto IS NULL OR NEW.monto <= 0 THEN
        RAISE EXCEPTION 'El monto de la transacción debe ser mayor que cero';
    END IF;

    IF NEW.id_cuenta_origen IS NULL AND NEW.id_cuenta_destino IS NULL THEN
        RAISE EXCEPTION 'La transacción debe tener al menos una cuenta origen o destino';
    END IF;

    IF NEW.id_cuenta_origen IS NOT NULL
       AND NEW.id_cuenta_destino IS NOT NULL
       AND NEW.id_cuenta_origen = NEW.id_cuenta_destino THEN
        RAISE EXCEPTION 'No se permite transferir dinero a la misma cuenta';
    END IF;

    IF NEW.id_cuenta_origen IS NOT NULL THEN
        SELECT id_cliente, estado, operaciones_suspendidas
          INTO v_propietario_origen, v_estado_origen, v_suspendida_origen
          FROM cuentas
         WHERE id_cuenta = NEW.id_cuenta_origen;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'La cuenta de origen no existe';
        END IF;

        IF v_propietario_origen <> NEW.id_cliente THEN
            RAISE EXCEPTION 'Solo puede enviar o retirar dinero desde una cuenta propia';
        END IF;

        IF v_estado_origen <> 'activo' OR v_suspendida_origen IS TRUE THEN
            RAISE EXCEPTION 'La cuenta de origen no está activa para operar';
        END IF;
    END IF;

    IF NEW.id_cuenta_destino IS NOT NULL THEN
        SELECT estado, operaciones_suspendidas
          INTO v_estado_destino, v_suspendida_destino
          FROM cuentas
         WHERE id_cuenta = NEW.id_cuenta_destino;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'La cuenta de destino no existe en el banco';
        END IF;

        IF v_estado_destino <> 'activo' OR v_suspendida_destino IS TRUE THEN
            RAISE EXCEPTION 'La cuenta de destino no está activa para recibir fondos';
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_validar_transaccion ON transacciones;
CREATE TRIGGER trg_validar_transaccion
    BEFORE INSERT ON transacciones
    FOR EACH ROW
    EXECUTE FUNCTION fn_validar_transaccion();

-- Trigger 3: Auditar automáticamente cambios de estado en transacciones
-- Atiende HU: Consultar estado de cuenta (financiera) y trazabilidad de operaciones
CREATE OR REPLACE FUNCTION fn_auditar_cambio_estado_transaccion()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF OLD.estado IS DISTINCT FROM NEW.estado THEN
        INSERT INTO eventos_transaccion (
            id_transaccion,
            tipo_evento,
            estado_anterior,
            estado_nuevo,
            detalle
        ) VALUES (
            NEW.id_transaccion,
            'cambio_estado',
            OLD.estado,
            NEW.estado,
            'Actualización automática de estado de transacción'
        );
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_auditar_cambio_estado_transaccion ON transacciones;
CREATE TRIGGER trg_auditar_cambio_estado_transaccion
    AFTER UPDATE OF estado ON transacciones
    FOR EACH ROW
    EXECUTE FUNCTION fn_auditar_cambio_estado_transaccion();

-- Trigger 4 y 5: Actualizar fecha_actualizacion automáticamente en cuentas y clientes
CREATE OR REPLACE FUNCTION fn_actualizar_fecha_modificacion()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.fecha_actualizacion := now();
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_actualizar_timestamp_cuentas ON cuentas;
CREATE TRIGGER trg_actualizar_timestamp_cuentas
    BEFORE UPDATE ON cuentas
    FOR EACH ROW
    EXECUTE FUNCTION fn_actualizar_fecha_modificacion();

DROP TRIGGER IF EXISTS trg_actualizar_timestamp_clientes ON clientes;
CREATE TRIGGER trg_actualizar_timestamp_clientes
    BEFORE UPDATE ON clientes
    FOR EACH ROW
    EXECUTE FUNCTION fn_actualizar_fecha_modificacion();

-- ============================================================================
-- 3. PROCEDIMIENTOS ALMACENADOS (CRITERIO 4)
-- ============================================================================

-- Procedimiento 1: Depositar dinero en una cuenta del banco
-- Atiende HU: Depositar dinero en una cuenta del banco / Aceptar solo un monto de depósito mayor que cero
CREATE OR REPLACE PROCEDURE sp_depositar_dinero(
    p_id_cliente    UUID,
    p_numero_cuenta VARCHAR(20),
    p_monto         NUMERIC(14, 2)
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_id_cuenta UUID;
    v_estado_cuenta VARCHAR(30);
    v_suspendida BOOLEAN;
    v_id_transaccion UUID;
BEGIN
    IF p_monto IS NULL OR p_monto <= 0 THEN
        RAISE EXCEPTION 'El monto de depósito debe ser mayor que cero';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM clientes WHERE id_cliente = p_id_cliente AND estado = 'activo'
    ) THEN
        RAISE EXCEPTION 'El cliente depositante no existe o no está activo';
    END IF;

    SELECT id_cuenta, estado, operaciones_suspendidas
      INTO v_id_cuenta, v_estado_cuenta, v_suspendida
      FROM cuentas
     WHERE numero_cuenta = trim(p_numero_cuenta)
       FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'La cuenta destino % no existe', p_numero_cuenta;
    END IF;

    IF v_estado_cuenta <> 'activo' OR v_suspendida IS TRUE THEN
        RAISE EXCEPTION 'La cuenta destino % se encuentra % y no admite depósitos', p_numero_cuenta, v_estado_cuenta;
    END IF;

    UPDATE cuentas
       SET saldo = saldo + p_monto
     WHERE id_cuenta = v_id_cuenta;

    INSERT INTO transacciones (
        id_cliente,
        id_cuenta_destino,
        monto,
        moneda,
        estado
    ) VALUES (
        p_id_cliente,
        v_id_cuenta,
        p_monto,
        'COP',
        'aprobado'
    )
    RETURNING id_transaccion INTO v_id_transaccion;

    INSERT INTO eventos_transaccion (
        id_transaccion,
        tipo_evento,
        estado_nuevo,
        detalle
    ) VALUES (
        v_id_transaccion,
        'deposito',
        'aprobado',
        'constancia de depósito por ' || p_monto::TEXT
    );
END;
$$;

-- Procedimiento 2: Retirar dinero de una cuenta propia
-- Atiende HU: Retirar dinero solo desde una cuenta propia / Retirar dinero de una cuenta propia / Aceptar solo un monto de retiro mayor que cero
CREATE OR REPLACE PROCEDURE sp_retirar_dinero(
    p_id_cliente    UUID,
    p_numero_cuenta VARCHAR(20),
    p_monto         NUMERIC(14, 2)
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_id_cuenta UUID;
    v_propietario UUID;
    v_estado_cuenta VARCHAR(30);
    v_suspendida BOOLEAN;
    v_saldo NUMERIC(19, 2);
    v_id_transaccion UUID;
BEGIN
    IF p_monto IS NULL OR p_monto <= 0 THEN
        RAISE EXCEPTION 'El monto de retiro debe ser mayor que cero';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM clientes WHERE id_cliente = p_id_cliente AND estado = 'activo'
    ) THEN
        RAISE EXCEPTION 'El perfil del cliente no se encuentra activo';
    END IF;

    SELECT id_cuenta, id_cliente, estado, operaciones_suspendidas, saldo
      INTO v_id_cuenta, v_propietario, v_estado_cuenta, v_suspendida, v_saldo
      FROM cuentas
     WHERE numero_cuenta = trim(p_numero_cuenta)
       FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'No existe una cuenta con el número %', p_numero_cuenta;
    END IF;

    IF v_propietario <> p_id_cliente THEN
        RAISE EXCEPTION 'Solo puede retirar dinero de una cuenta propia';
    END IF;

    IF v_estado_cuenta <> 'activo' OR v_suspendida IS TRUE THEN
        RAISE EXCEPTION 'La cuenta % no se encuentra activa', p_numero_cuenta;
    END IF;

    IF v_saldo < p_monto THEN
        RAISE EXCEPTION 'Saldo insuficiente para realizar el retiro';
    END IF;

    UPDATE cuentas
       SET saldo = saldo - p_monto
     WHERE id_cuenta = v_id_cuenta;

    INSERT INTO retiros (
        id_cliente,
        id_cuenta,
        monto
    ) VALUES (
        p_id_cliente,
        v_id_cuenta,
        p_monto
    );

    INSERT INTO transacciones (
        id_cliente,
        id_cuenta_origen,
        monto,
        moneda,
        estado
    ) VALUES (
        p_id_cliente,
        v_id_cuenta,
        p_monto,
        'COP',
        'aprobado'
    )
    RETURNING id_transaccion INTO v_id_transaccion;

    INSERT INTO eventos_transaccion (
        id_transaccion,
        tipo_evento,
        estado_nuevo,
        detalle
    ) VALUES (
        v_id_transaccion,
        'retiro',
        'aprobado',
        'retiro exitoso por ' || p_monto::TEXT
    );
END;
$$;

-- Procedimiento 3: Transferir dinero a otra cuenta del mismo banco
-- Atiende HU: Enviar dinero solo desde una cuenta propia / Impedir transferencia a la misma cuenta / Aceptar solo un monto mayor que cero / Transferir dinero a otra cuenta del mismo banco
CREATE OR REPLACE PROCEDURE sp_transferir_dinero(
    p_id_cliente            UUID,
    p_numero_cuenta_origen  VARCHAR(20),
    p_numero_cuenta_destino VARCHAR(20),
    p_monto                 NUMERIC(14, 2),
    p_referencia_externa    VARCHAR(100) DEFAULT NULL
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_id_origen UUID;
    v_propietario_origen UUID;
    v_estado_origen VARCHAR(30);
    v_suspendida_origen BOOLEAN;
    v_saldo_origen NUMERIC(19, 2);
    v_id_destino UUID;
    v_estado_destino VARCHAR(30);
    v_suspendida_destino BOOLEAN;
    v_id_transaccion UUID;
BEGIN
    IF p_monto IS NULL OR p_monto <= 0 THEN
        RAISE EXCEPTION 'El monto a transferir debe ser mayor que cero';
    END IF;

    IF trim(p_numero_cuenta_origen) = trim(p_numero_cuenta_destino) THEN
        RAISE EXCEPTION 'No es posible transferir dinero a la misma cuenta';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM clientes WHERE id_cliente = p_id_cliente AND estado = 'activo'
    ) THEN
        RAISE EXCEPTION 'El perfil del cliente ordenante no se encuentra activo';
    END IF;

    -- Bloqueo en orden determinístico para prevenir interbloqueos (deadlocks)
    PERFORM 1
      FROM cuentas
     WHERE numero_cuenta IN (trim(p_numero_cuenta_origen), trim(p_numero_cuenta_destino))
     ORDER BY id_cuenta
       FOR UPDATE;

    SELECT id_cuenta, id_cliente, estado, operaciones_suspendidas, saldo
      INTO v_id_origen, v_propietario_origen, v_estado_origen, v_suspendida_origen, v_saldo_origen
      FROM cuentas
     WHERE numero_cuenta = trim(p_numero_cuenta_origen);

    IF NOT FOUND THEN
        RAISE EXCEPTION 'La cuenta de origen % no existe', p_numero_cuenta_origen;
    END IF;

    IF v_propietario_origen <> p_id_cliente THEN
        RAISE EXCEPTION 'Solo puede enviar dinero desde una cuenta propia';
    END IF;

    IF v_estado_origen <> 'activo' OR v_suspendida_origen IS TRUE THEN
        RAISE EXCEPTION 'La cuenta de origen % no se encuentra activa', p_numero_cuenta_origen;
    END IF;

    SELECT id_cuenta, estado, operaciones_suspendidas
      INTO v_id_destino, v_estado_destino, v_suspendida_destino
      FROM cuentas
     WHERE numero_cuenta = trim(p_numero_cuenta_destino);

    IF NOT FOUND THEN
        RAISE EXCEPTION 'La cuenta de destino % no existe en el banco', p_numero_cuenta_destino;
    END IF;

    IF v_estado_destino <> 'activo' OR v_suspendida_destino IS TRUE THEN
        RAISE EXCEPTION 'La cuenta de destino % no se encuentra activa', p_numero_cuenta_destino;
    END IF;

    IF v_saldo_origen < p_monto THEN
        RAISE EXCEPTION 'Saldo insuficiente en la cuenta de origen para completar la transferencia';
    END IF;

    UPDATE cuentas
       SET saldo = saldo - p_monto
     WHERE id_cuenta = v_id_origen;

    UPDATE cuentas
       SET saldo = saldo + p_monto
     WHERE id_cuenta = v_id_destino;

    INSERT INTO transacciones (
        id_cliente,
        id_cuenta_origen,
        id_cuenta_destino,
        monto,
        moneda,
        estado,
        referencia_externa
    ) VALUES (
        p_id_cliente,
        v_id_origen,
        v_id_destino,
        p_monto,
        'COP',
        'aprobado',
        p_referencia_externa
    )
    RETURNING id_transaccion INTO v_id_transaccion;

    INSERT INTO eventos_transaccion (
        id_transaccion,
        tipo_evento,
        estado_nuevo,
        detalle
    ) VALUES (
        v_id_transaccion,
        'transferencia',
        'aprobado',
        'Transferencia exitosa desde ' || trim(p_numero_cuenta_origen) ||
        ' hacia ' || trim(p_numero_cuenta_destino) || ' por ' || p_monto::TEXT
    );
END;
$$;

-- ============================================================================
-- 4. ROLES, PRIVILEGIOS Y SEGURIDAD RLS (CRITERIO 6)
-- ============================================================================

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'rol_admin') THEN
        CREATE ROLE rol_admin NOLOGIN;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'rol_app') THEN
        CREATE ROLE rol_app NOLOGIN;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'rol_lectura') THEN
        CREATE ROLE rol_lectura NOLOGIN;
    END IF;
END;
$$;

REVOKE CREATE ON SCHEMA public FROM PUBLIC;
GRANT USAGE ON SCHEMA public TO rol_admin, rol_app, rol_lectura;

-- Privilegios sobre tablas (principio de mínimo privilegio)
GRANT ALL ON ALL TABLES IN SCHEMA public TO rol_admin;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO rol_admin, rol_app;

GRANT SELECT, INSERT, UPDATE ON clientes, cuentas, transacciones TO rol_app;
GRANT SELECT, INSERT ON eventos_transaccion, retiros TO rol_app;
REVOKE UPDATE, DELETE ON eventos_transaccion, retiros FROM rol_app;

GRANT SELECT ON clientes, cuentas, transacciones, eventos_transaccion, retiros TO rol_lectura;

-- Privilegios sobre procedimientos almacenados del Sprint 3
REVOKE EXECUTE ON PROCEDURE sp_depositar_dinero(UUID, VARCHAR, NUMERIC) FROM PUBLIC;
REVOKE EXECUTE ON PROCEDURE sp_retirar_dinero(UUID, VARCHAR, NUMERIC) FROM PUBLIC;
REVOKE EXECUTE ON PROCEDURE sp_transferir_dinero(UUID, VARCHAR, VARCHAR, NUMERIC, VARCHAR) FROM PUBLIC;

GRANT EXECUTE ON PROCEDURE sp_depositar_dinero(UUID, VARCHAR, NUMERIC) TO rol_admin, rol_app;
GRANT EXECUTE ON PROCEDURE sp_retirar_dinero(UUID, VARCHAR, NUMERIC) TO rol_admin, rol_app;
GRANT EXECUTE ON PROCEDURE sp_transferir_dinero(UUID, VARCHAR, VARCHAR, NUMERIC, VARCHAR) TO rol_admin, rol_app;

-- Políticas de Row Level Security (RLS) compatibles con Supabase
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated')
       AND EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = 'auth') THEN

        ALTER TABLE clientes ENABLE ROW LEVEL SECURITY;
        ALTER TABLE cuentas ENABLE ROW LEVEL SECURITY;
        ALTER TABLE transacciones ENABLE ROW LEVEL SECURITY;
        ALTER TABLE retiros ENABLE ROW LEVEL SECURITY;

        DROP POLICY IF EXISTS clientes_propio_select ON clientes;
        CREATE POLICY clientes_propio_select ON clientes
            FOR SELECT TO authenticated
            USING (id_cliente = auth.uid());

        DROP POLICY IF EXISTS cuentas_propias_select ON cuentas;
        CREATE POLICY cuentas_propias_select ON cuentas
            FOR SELECT TO authenticated
            USING (id_cliente = auth.uid());

        DROP POLICY IF EXISTS transacciones_propias_select ON transacciones;
        CREATE POLICY transacciones_propias_select ON transacciones
            FOR SELECT TO authenticated
            USING (
                id_cliente = auth.uid()
                OR id_cuenta_origen IN (SELECT id_cuenta FROM cuentas WHERE id_cliente = auth.uid())
                OR id_cuenta_destino IN (SELECT id_cuenta FROM cuentas WHERE id_cliente = auth.uid())
            );

        DROP POLICY IF EXISTS retiros_propios_select ON retiros;
        CREATE POLICY retiros_propios_select ON retiros
            FOR SELECT TO authenticated
            USING (id_cliente = auth.uid());
    END IF;
END;
$$;
