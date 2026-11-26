# BD-EAV08-2026-2
Repositorio para entregables propios de la materia de Bases de datos y laboratorios del equipo avanzado 8 de la edición 26-2 de CodeF@ctory, equipo conformado por:

YEPES JARAMILLO ANGEL SIMON: angel.yepes2@udea.edu.co
FORERO AGUDELO CARLOS ALBERTO: carlos.forero@udea.edu.co
ALBORNOZ VILLADIEGO JOSÉ FERNANDO: jose.albornoz@udea.edu.co
CONTRERAS PUELLO SAMUEL ESTEBAN: samuel.contreras@udea.edu.co

# CAMBIOS RESPECTO AL SPRINT 2

Para el **Sprint 3** (Motor Transaccional), el modelo de datos, el script físico, las consultas y el esquema de seguridad tuvieron muchos cambios respecto al Sprint 2, explicados asi:

1. **Nueva tabla `retiros`:** incorporamos la entidad `retiros` (`id_retiro`, `id_cliente`, `id_cuenta`, `monto`, `fecha`) para guardar el comprobante específico de cada retiro hecho por un cliente sobre una cuenta propia (`RetiroService`), manteniendo además el registro propio del movimiento en `transacciones` (`id_cuenta_origen`) y su trazabilidad en `eventos_transaccion` (`tipo_evento = 'retiro'`).
2. **Ajustes del MER respecto al entregado/usado en el Sprint 2:** Se eliminó del MER y de la matriz de seguridad las tablas `credenciales_api` y `reportes`, ya que quedaron fuera del alcance del core bancario implementado (`BackendBank`), dejando el modelo 100% consistente con las 5 tablas físicas en producción (`clientes`, `cuentas`, `transacciones`, `eventos_transaccion`, `retiros`) esto porque quedaba fuera del alcance propuesto para el sprint 3 ya que nos enfocamos en terminar el motor transaccional.
3. **Nuevas restricciones de integridad e índices en `transacciones` y `retiros`:**
   - Restricción `CHECK (id_cuenta_origen IS DISTINCT FROM id_cuenta_destino)` en `transacciones` para impedir transferencias hacia la misma cuenta a nivel de motor.
   - Restricción `CHECK (monto > 0)` en `transacciones` y `retiros` para garantizar montos estrictamente positivos en depósitos, retiros y transferencias.
   - Nuevos índices (`idx_cuentas_cliente_estado`, `idx_transacciones_cliente`, `idx_transacciones_estado`, `idx_transacciones_fecha`, `idx_transacciones_origen`, `idx_transacciones_destino`, `idx_retiros_cuenta`, `idx_retiros_cliente`, `idx_eventos_transaccion_id`) para optimizar consultas de estado de cuenta, historial de movimientos y validaciones de saldo.
4. **Automatización y reglas de negocio en base de datos (Triggers y Procedimientos):**
   - Se agregan **5 triggers** para validar titularidad de cuenta en retiros y transferencias, impedir transferencias a la misma cuenta, validar montos mayores a cero, auditar automáticamente cambios de estado en `transacciones` y actualizar `fecha_actualizacion`.
   - Se agregan **3 procedimientos almacenados** (`sp_depositar_dinero`, `sp_retirar_dinero`, `sp_transferir_dinero`) que encapsulan de forma atómica y transaccional las operaciones monetarias del Sprint 3.
5. **Actualización de consultas y seguridad:** Se ajustan las consultas de los Sprints 1 y 2 al esquema refinado, se añaden consultas para las HU del Sprint 3 y se actualiza la matriz de permisos (`GRANT`/`REVOKE` y políticas RLS) incluyendo `retiros` y los permisos `EXECUTE` sobre los procedimientos almacenados.

---

# Criterio 1 - MER Refinado

### Entidades y Relaciones

| Entidad | Descripción |
|---|---|
| `clientes` | Clientes/usuarios registrados en la plataforma bancaria, con credenciales, estado operativo, rol y auditoría de cambios |
| `cuentas` | Cuentas financieras vinculadas a cada cliente, con número de cuenta único, saldo disponible y estado operativo |
| `transacciones` | Movimientos financieros procesados (depósitos, retiros y transferencias entre cuentas del banco) |
| `eventos_transaccion` | Bitácora inmutable de auditoría que registra cada evento o cambio de estado de una transacción |
| `retiros` | Registro detallado de los retiros realizados por un cliente desde una de sus cuentas propias |

### Relaciones y cardinalidad

- Un `cliente` puede poseer cero o muchas `cuentas` (máximo 3 activas por regla de negocio); una `cuenta` pertenece a uno y solo un `cliente`.
- Un `cliente` puede ser actualizado por otro `cliente` con rol `ADMINISTRADOR` (`actualizado_por`); un administrador puede actualizar cero o muchos clientes.
- Un `cliente` puede originar cero o muchas `transacciones`; una `transacción` es originada por uno y solo un `cliente`.
- Una `cuenta` puede actuar como cuenta origen de cero o muchas `transacciones` y como cuenta destino de cero o muchas `transacciones`.
- Una `transacción` genera uno o muchos `eventos_transaccion`; cada evento pertenece a una y solo una `transacción`.
- Un `cliente` puede realizar cero o muchos `retiros` sobre sus `cuentas` propias; cada `retiro` pertenece a un `cliente` y a una `cuenta`.

### Diagrama E-R (Mermaid)

```mermaid
erDiagram
    CLIENTES ||--o{ CUENTAS : posee
    CLIENTES ||--o{ CLIENTES : "actualiza a"
    CLIENTES ||--o{ TRANSACCIONES : origina
    CLIENTES ||--o{ RETIROS : realiza
    CUENTAS ||--o{ TRANSACCIONES : "cuenta origen"
    CUENTAS ||--o{ TRANSACCIONES : "cuenta destino"
    CUENTAS ||--o{ RETIROS : "afecta saldo"
    TRANSACCIONES ||--o{ EVENTOS_TRANSACCION : registra

    CLIENTES {
        uuid id_cliente PK
        varchar nombre_comercial
        varchar razon_social
        varchar nit_documento UK
        varchar email UK
        varchar usuario UK
        varchar contrasena
        varchar telefono
        varchar estado
        timestamptz fecha_registro
        varchar rol
        uuid actualizado_por FK
        timestamptz fecha_actualizacion
        varchar motivo
        int intentos_fallidos
        timestamptz bloqueado_hasta
    }

    CUENTAS {
        uuid id_cuenta PK
        uuid id_cliente FK
        varchar numero_cuenta UK
        varchar estado
        numeric saldo
        varchar motivo
        boolean operaciones_suspendidas
        timestamptz fecha_vinculacion
        timestamptz fecha_actualizacion
    }

    TRANSACCIONES {
        uuid id_transaccion PK
        uuid id_cliente FK
        uuid id_cuenta_origen FK
        uuid id_cuenta_destino FK
        numeric monto
        char moneda
        varchar estado
        varchar referencia_externa UK
        timestamptz fecha_creacion
        timestamptz fecha_actualizacion
    }

    EVENTOS_TRANSACCION {
        bigint id_evento PK
        uuid id_transaccion FK
        varchar tipo_evento
        varchar estado_anterior
        varchar estado_nuevo
        text detalle
        timestamptz fecha_evento
    }

    RETIROS {
        uuid id_retiro PK
        uuid id_cliente FK
        uuid id_cuenta FK
        numeric monto
        timestamptz fecha
    }
```

# Criterio 2 - Modelo físico completo (claves y restricciones)

Todas las tablas cumplen **3FN / BCNF**: cada atributo no clave depende de forma completa y no transitiva de su clave primaria, eliminando anomalías de inserción, actualización y borrado.

Ver script ejecutable completo en [`schema.sql`](./schema.sql).

### Tipos de datos y restricciones por tabla

#### `clientes`

| Columna | Tipo de dato | Restricciones |
|---|---|---|
| `id_cliente` | UUID | **PK**, `DEFAULT gen_random_uuid()` |
| `nombre_comercial` | VARCHAR(150) | NOT NULL |
| `razon_social` | VARCHAR(200) | NOT NULL |
| `nit_documento` | VARCHAR(30) | NOT NULL, UNIQUE |
| `email` | VARCHAR(150) | NOT NULL, UNIQUE |
| `usuario` | VARCHAR(80) | NOT NULL, UNIQUE |
| `contrasena` | VARCHAR(255) | NOT NULL (hash BCrypt) |
| `telefono` | VARCHAR(20) | — |
| `estado` | VARCHAR(30) | NOT NULL, `DEFAULT 'activo'`, CHECK IN (`pendiente_de_validacion`, `activo`, `inactivo`, `bloqueado`) |
| `fecha_registro` | TIMESTAMPTZ | NOT NULL, `DEFAULT now()` |
| `rol` | VARCHAR(20) | NOT NULL, `DEFAULT 'CLIENTE'`, CHECK IN (`CLIENTE`, `ADMINISTRADOR`) |
| `actualizado_por` | UUID | **FK** → `clientes(id_cliente)` |
| `fecha_actualizacion` | TIMESTAMPTZ | — |
| `motivo` | VARCHAR(200) | — |
| `intentos_fallidos` | INTEGER | NOT NULL, `DEFAULT 0` |
| `bloqueado_hasta` | TIMESTAMPTZ | — |

#### `cuentas`

| Columna | Tipo de dato | Restricciones |
|---|---|---|
| `id_cuenta` | UUID | **PK**, `DEFAULT gen_random_uuid()` |
| `id_cliente` | UUID | NOT NULL, **FK** → `clientes(id_cliente)` |
| `numero_cuenta` | VARCHAR(20) | NOT NULL, UNIQUE |
| `estado` | VARCHAR(30) | NOT NULL, `DEFAULT 'activo'`, CHECK IN (`activo`, `inactivo`, `bloqueado`) |
| `saldo` | NUMERIC(19,2) | NOT NULL, `DEFAULT 0`, CHECK (`saldo >= 0`) |
| `motivo` | VARCHAR(200) | — |
| `operaciones_suspendidas` | BOOLEAN | NOT NULL, `DEFAULT FALSE` |
| `fecha_vinculacion` | TIMESTAMPTZ | NOT NULL, `DEFAULT now()` |
| `fecha_actualizacion` | TIMESTAMPTZ | — |

#### `transacciones`

| Columna | Tipo de dato | Restricciones |
|---|---|---|
| `id_transaccion` | UUID | **PK**, `DEFAULT gen_random_uuid()` |
| `id_cliente` | UUID | NOT NULL, **FK** → `clientes(id_cliente)` ON DELETE RESTRICT |
| `id_cuenta_origen` | UUID | **FK** → `cuentas(id_cuenta)` ON DELETE RESTRICT (NULL en depósitos) |
| `id_cuenta_destino` | UUID | **FK** → `cuentas(id_cuenta)` ON DELETE RESTRICT (NULL en retiros) |
| `monto` | NUMERIC(14,2) | NOT NULL, CHECK (`monto > 0`) |
| `moneda` | CHAR(3) | NOT NULL, `DEFAULT 'COP'` |
| `estado` | VARCHAR(20) | NOT NULL, `DEFAULT 'creado'`, CHECK IN (`creado`, `aprobado`, `rechazado`, `reembolsado`) |
| `referencia_externa` | VARCHAR(100) | UNIQUE |
| `fecha_creacion` | TIMESTAMPTZ | NOT NULL, `DEFAULT now()` |
| `fecha_actualizacion` | TIMESTAMPTZ | NOT NULL, `DEFAULT now()` |

Restricción a nivel de tabla: `CHECK (id_cuenta_origen IS DISTINCT FROM id_cuenta_destino)`.

#### `eventos_transaccion`

| Columna | Tipo de dato | Restricciones |
|---|---|---|
| `id_evento` | BIGINT | **PK**, `GENERATED ALWAYS AS IDENTITY` |
| `id_transaccion` | UUID | NOT NULL, **FK** → `transacciones(id_transaccion)` ON DELETE CASCADE |
| `tipo_evento` | VARCHAR(50) | NOT NULL (`deposito`, `retiro`, `transferencia`, `cambio_estado`) |
| `estado_anterior` | VARCHAR(20) | — |
| `estado_nuevo` | VARCHAR(20) | — |
| `detalle` | TEXT | — |
| `fecha_evento` | TIMESTAMPTZ | NOT NULL, `DEFAULT now()` |

#### `retiros`

| Columna | Tipo de dato | Restricciones |
|---|---|---|
| `id_retiro` | UUID | **PK**, `DEFAULT gen_random_uuid()` |
| `id_cliente` | UUID | NOT NULL, **FK** → `clientes(id_cliente)` |
| `id_cuenta` | UUID | NOT NULL, **FK** → `cuentas(id_cuenta)` |
| `monto` | NUMERIC(14,2) | NOT NULL, CHECK (`monto > 0`) |
| `fecha` | TIMESTAMPTZ | NOT NULL, `DEFAULT now()` |

---

# Criterio 3 - Triggers coherentes con las HU

Los siguientes triggers están implementados en [`schema.sql`](./schema.sql) para blindar las reglas de negocio directamente en PostgreSQL:

| Trigger | Tabla | Momento y Evento | HU que atiende | Propósito |
|---|---|---|---|---|
| `trg_validar_retiro` | `retiros` | `BEFORE INSERT` | *Retirar dinero solo desde una cuenta propia*; *Retirar dinero de una cuenta propia*; *Aceptar solo un monto de retiro mayor que cero* | Verifica que `monto > 0`, que la cuenta exista, que pertenezca al cliente (`id_cliente`), y que la cuenta esté en estado `'activo'` con `operaciones_suspendidas = FALSE`. |
| `trg_validar_transaccion` | `transacciones` | `BEFORE INSERT` | *Depositar dinero en una cuenta del banco*; *Enviar dinero solo desde una cuenta propia*; *Impedir la transferencia a la misma cuenta*; *Aceptar solo un monto mayor que cero*; *Transferir dinero a otra cuenta del mismo banco* | Valida que `monto > 0`, que exista al menos una cuenta involucrada, que origen y destino sean distintos, que la cuenta origen (si aplica) pertenezca al cliente y esté activa, y que la cuenta destino (si aplica) exista en el banco y esté activa. |
| `trg_auditar_cambio_estado_transaccion` | `transacciones` | `AFTER UPDATE OF estado` | *Consultar estado de cuenta (financiera)* (Sprint 2) y trazabilidad de *Transferir / Depositar / Retirar* (Sprint 3) | Registra automáticamente un evento en `eventos_transaccion` cada vez que cambia el estado de una transacción (`estado_anterior` → `estado_nuevo`). |
| `trg_actualizar_timestamp_cuentas` | `cuentas` | `BEFORE UPDATE` | *Bloquear cuenta (financiera)* (Sprint 2); *Depositar / Retirar / Transferir dinero* (Sprint 3) | Actualiza automáticamente `fecha_actualizacion = now()` cada vez que se modifica el saldo o el estado de una cuenta. |
| `trg_actualizar_timestamp_clientes` | `clientes` | `BEFORE UPDATE` | *Actualizar datos del perfil de un cliente*; *Cambiar el estado de un cliente (activo/inactivo)* (Sprint 1) | Actualiza automáticamente `fecha_actualizacion = now()` ante cualquier modificación en el perfil o estado del cliente. |

---
# Criterio 4 - Procedimientos coherentes con las HU

Los siguientes procedimientos almacenados en [`schema.sql`](./schema.sql) encapsulan de forma atómica las operaciones monetarias del **Sprint 3**:

### 1. `sp_depositar_dinero`
- **HU que atiende:** *Depositar dinero en una cuenta del banco*, *Aceptar solo un monto de depósito mayor que cero*.
- **Parámetros:**
  - `p_id_cliente UUID` (cliente autenticado que realiza el depósito)
  - `p_numero_cuenta VARCHAR(20)` (número de cuenta destino en el banco)
  - `p_monto NUMERIC(14,2)` (monto a depositar, debe ser `> 0`)
- **Comportamiento:** Valida que el monto sea positivo y que la cuenta destino exista y esté `'activo'` sin operaciones suspendidas; incrementa `cuentas.saldo`, registra la transacción aprobada en `transacciones` (`id_cuenta_destino`) y crea la constancia en `eventos_transaccion` (`tipo_evento = 'deposito'`).
- **Ejemplo de llamada:**
  ```sql
  CALL sp_depositar_dinero(
      '11111111-1111-1111-1111-111111111111',
      '1000000001',
      250000.00
  );
  ```

### 2. `sp_retirar_dinero`
- **HU que atiende:** *Retirar dinero solo desde una cuenta propia*, *Retirar dinero de una cuenta propia*, *Aceptar solo un monto de retiro mayor que cero*.
- **Parámetros:**
  - `p_id_cliente UUID` (cliente autenticado propietario de la cuenta)
  - `p_numero_cuenta VARCHAR(20)` (número de cuenta propia desde donde se retira)
  - `p_monto NUMERIC(14,2)` (monto a retirar, debe ser `> 0` y `<= saldo`)
- **Comportamiento:** Bloquea la fila de la cuenta (`FOR UPDATE`), verifica que el cliente esté `'activo'`, que la cuenta pertenezca a `p_id_cliente`, que esté `'activo'` sin operaciones suspendidas y que tenga saldo suficiente; descuenta `cuentas.saldo`, inserta el registro en `retiros`, registra la transacción aprobada en `transacciones` (`id_cuenta_origen`) y genera el evento en `eventos_transaccion` (`tipo_evento = 'retiro'`).
- **Ejemplo de llamada:**
  ```sql
  CALL sp_retirar_dinero(
      '11111111-1111-1111-1111-111111111111',
      '1000000001',
      80000.00
  );
  ```

### 3. `sp_transferir_dinero`
- **HU que atiende:** *Enviar dinero solo desde una cuenta propia*, *Impedir la transferencia a la misma cuenta*, *Aceptar solo un monto mayor que cero*, *Transferir dinero a otra cuenta del mismo banco*.
- **Parámetros:**
  - `p_id_cliente UUID` (cliente autenticado propietario de la cuenta origen)
  - `p_numero_cuenta_origen VARCHAR(20)` (cuenta propia debitada)
  - `p_numero_cuenta_destino VARCHAR(20)` (cuenta destino del mismo banco)
  - `p_monto NUMERIC(14,2)` (monto a transferir, debe ser `> 0`)
  - `p_referencia_externa VARCHAR(100) DEFAULT NULL` (referencia opcional única)
- **Comportamiento:** Valida que `p_monto > 0` y que `p_numero_cuenta_origen <> p_numero_cuenta_destino`; bloquea ambas cuentas en orden determinístico por `id_cuenta` para evitar interbloqueos (*deadlocks*); verifica que el cliente esté `'activo'`, que la cuenta origen pertenezca a `p_id_cliente`, que ambas cuentas estén `'activo'` sin operaciones suspendidas y que la cuenta origen tenga saldo suficiente; debita la cuenta origen, acredita la cuenta destino, registra la transacción aprobada en `transacciones` y guarda la auditoría en `eventos_transaccion` (`tipo_evento = 'transferencia'`).
- **Ejemplo de llamada:**
  ```sql
  CALL sp_transferir_dinero(
      '11111111-1111-1111-1111-111111111111',
      '1000000001',
      '1000000002',
      120000.00,
      'TRF-2026-0001'
  );
  ```
---
# Criterio 5 - Consultas actualizadas (Sprints 1, 2 y 3)

### Consultas de Sprints 1 y 2 ajustadas al esquema refinado

```sql
-- 1. [Sprint 1 - HU: Consultar actividad/clientes] Top 10 clientes con mayor volumen de transacciones aprobadas en el último mes
SELECT c.id_cliente, c.nombre_comercial, SUM(t.monto) AS volumen_aprobado
FROM transacciones t
JOIN clientes c ON c.id_cliente = t.id_cliente
WHERE t.estado = 'aprobado'
  AND t.fecha_creacion >= date_trunc('month', now()) - interval '1 month'
  AND t.fecha_creacion <  date_trunc('month', now())
GROUP BY c.id_cliente, c.nombre_comercial
ORDER BY volumen_aprobado DESC
LIMIT 10;

-- 2. [Sprint 1 - HU: Restringir acciones según rol / Auditoría] Administradores por número de cambios realizados sobre perfiles de clientes
SELECT admin.nombre_comercial AS administrador, COUNT(*) AS cambios_realizados
FROM clientes afectado
JOIN clientes admin ON admin.id_cliente = afectado.actualizado_por
GROUP BY admin.nombre_comercial
ORDER BY cambios_realizados DESC;

-- 3. [Sprint 2 - HU: Autenticarse en el sistema] Clientes bloqueados temporalmente por intentos fallidos de inicio de sesión
SELECT id_cliente, usuario, nombre_comercial, intentos_fallidos, bloqueado_hasta
FROM clientes
WHERE bloqueado_hasta IS NOT NULL
  AND bloqueado_hasta > now();

-- 4. [Sprint 2 - HU: Consultar saldo disponible] Saldo total disponible por cliente sumando sus cuentas activas
SELECT c.id_cliente, c.nombre_comercial, COUNT(cu.id_cuenta) AS cuentas_activas, SUM(cu.saldo) AS saldo_total
FROM clientes c
JOIN cuentas cu ON cu.id_cliente = c.id_cliente
WHERE cu.estado = 'activo'
  AND cu.operaciones_suspendidas = FALSE
GROUP BY c.id_cliente, c.nombre_comercial
ORDER BY saldo_total DESC;

-- 5. [Sprint 2 - HU: Bloquear cuenta financiera] Cuentas bloqueadas o con operaciones suspendidas y su motivo
SELECT cu.numero_cuenta, c.nombre_comercial, cu.estado, cu.operaciones_suspendidas, cu.motivo, cu.fecha_actualizacion
FROM cuentas cu
JOIN clientes c ON c.id_cliente = cu.id_cliente
WHERE cu.estado = 'bloqueado' OR cu.operaciones_suspendidas = TRUE;

-- 6. [Sprint 2 - HU: Consultar estado de cuenta financiera] Estado actual y resumen de movimientos de una cuenta específica
SELECT cu.numero_cuenta,
       c.nombre_comercial AS titular,
       cu.estado,
       cu.saldo AS saldo_disponible,
       COUNT(t.id_transaccion) AS total_movimientos
FROM cuentas cu
JOIN clientes c ON c.id_cliente = cu.id_cliente
LEFT JOIN transacciones t
       ON t.id_cuenta_origen = cu.id_cuenta OR t.id_cuenta_destino = cu.id_cuenta
WHERE cu.numero_cuenta = '1000000001'
GROUP BY cu.numero_cuenta, c.nombre_comercial, cu.estado, cu.saldo;
```

### Consultas nuevas del Sprint 3

```sql
-- 7. [Sprint 3 - HU: Retirar dinero solo desde una cuenta propia / Retirar dinero de una cuenta propia]
-- Historial de retiros realizados por un cliente sobre sus cuentas propias
SELECT r.id_retiro,
       c.nombre_comercial AS titular,
       cu.numero_cuenta,
       r.monto,
       r.fecha
FROM retiros r
JOIN clientes c ON c.id_cliente = r.id_cliente
JOIN cuentas cu ON cu.id_cuenta = r.id_cuenta
WHERE r.id_cliente = '11111111-1111-1111-1111-111111111111'
ORDER BY r.fecha DESC;

-- 8. [Sprint 3 - HU: Depositar dinero en una cuenta del banco]
-- Listado de depósitos aprobados recibidos por una cuenta con su constancia de auditoría
SELECT t.id_transaccion,
       cu_dest.numero_cuenta AS cuenta_destino,
       c_orig.nombre_comercial AS depositante,
       t.monto,
       t.moneda,
       e.detalle AS constancia,
       t.fecha_creacion
FROM transacciones t
JOIN cuentas cu_dest ON cu_dest.id_cuenta = t.id_cuenta_destino
JOIN clientes c_orig ON c_orig.id_cliente = t.id_cliente
LEFT JOIN eventos_transaccion e
       ON e.id_transaccion = t.id_transaccion AND e.tipo_evento = 'deposito'
WHERE t.id_cuenta_origen IS NULL
  AND t.id_cuenta_destino IS NOT NULL
  AND t.estado = 'aprobado'
ORDER BY t.fecha_creacion DESC;

-- 9. [Sprint 3 - HU: Transferir dinero a otra cuenta del mismo banco / Enviar dinero solo desde una cuenta propia]
-- Historial de transferencias entre cuentas del banco con identificación de cuenta origen y cuenta destino
SELECT t.id_transaccion,
       c.nombre_comercial AS ordenante,
       cu_orig.numero_cuenta AS cuenta_origen,
       cu_dest.numero_cuenta AS cuenta_destino,
       t.monto,
       t.moneda,
       t.estado,
       t.referencia_externa,
       t.fecha_creacion
FROM transacciones t
JOIN clientes c ON c.id_cliente = t.id_cliente
JOIN cuentas cu_orig ON cu_orig.id_cuenta = t.id_cuenta_origen
JOIN cuentas cu_dest ON cu_dest.id_cuenta = t.id_cuenta_destino
WHERE t.id_cuenta_origen IS NOT NULL
  AND t.id_cuenta_destino IS NOT NULL
ORDER BY t.fecha_creacion DESC;

-- 10. [Sprint 3 - HU: Consultar extracto unificado de depósitos, retiros y transferencias por cuenta]
-- Extracto cronológico de entradas y salidas de una cuenta financiera
SELECT t.id_transaccion,
       t.fecha_creacion,
       CASE
           WHEN t.id_cuenta_origen IS NULL AND t.id_cuenta_destino = cu.id_cuenta THEN 'DEPOSITO'
           WHEN t.id_cuenta_destino IS NULL AND t.id_cuenta_origen = cu.id_cuenta THEN 'RETIRO'
           WHEN t.id_cuenta_origen = cu.id_cuenta THEN 'TRANSFERENCIA_ENVIADA'
           ELSE 'TRANSFERENCIA_RECIBIDA'
       END AS tipo_operacion,
       CASE
           WHEN t.id_cuenta_destino = cu.id_cuenta THEN t.monto
           ELSE -t.monto
       END AS impacto_saldo,
       t.estado
FROM transacciones t
JOIN cuentas cu ON cu.id_cuenta IN (t.id_cuenta_origen, t.id_cuenta_destino)
WHERE cu.numero_cuenta = '1000000001'
ORDER BY t.fecha_creacion DESC;
```

---
# Criterio 6 - Roles y esquema de seguridad actualizados

Siguiendo el **principio de mínimo privilegio**, se mantienen los tres roles de motor (`rol_admin`, `rol_app`, `rol_lectura`) y se actualizan sus privilegios respecto al Sprint 2 para cubrir la nueva tabla `retiros` y los tres procedimientos almacenados (`sp_depositar_dinero`, `sp_retirar_dinero`, `sp_transferir_dinero`).

### Cambios en seguridad frente al Sprint 2
- **Tabla `retiros`:** Se otorga `SELECT, INSERT` a `rol_app` (sin `UPDATE` ni `DELETE` para preservar la inmutabilidad del registro de retiros), `SELECT` a `rol_lectura` y `ALL` a `rol_admin`.
- **Procedimientos almacenados (`EXECUTE`):** Se revoca `EXECUTE` a `PUBLIC` y se otorga `EXECUTE` exclusivamente a `rol_app` y `rol_admin` sobre `sp_depositar_dinero`, `sp_retirar_dinero` y `sp_transferir_dinero`. `rol_lectura` no tiene permiso de ejecución sobre operaciones monetarias.

### Matriz actualizada rol × objeto

| Objeto / Tabla | `rol_admin` | `rol_app` | `rol_lectura` |
|---|---|---|---|
| `clientes` | `ALL` | `SELECT, INSERT, UPDATE` | `SELECT` |
| `cuentas` | `ALL` | `SELECT, INSERT, UPDATE` | `SELECT` |
| `transacciones` | `ALL` | `SELECT, INSERT, UPDATE` | `SELECT` |
| `eventos_transaccion` | `ALL` | `SELECT, INSERT` *(inmutable: sin UPDATE/DELETE)* | `SELECT` |
| `retiros` *(Nuevo Sprint 3)* | `ALL` | `SELECT, INSERT` *(inmutable: sin UPDATE/DELETE)* | `SELECT` |
| `sp_depositar_dinero` *(Nuevo Sprint 3)* | `EXECUTE` | `EXECUTE` | — |
| `sp_retirar_dinero` *(Nuevo Sprint 3)* | `EXECUTE` | `EXECUTE` | — |
| `sp_transferir_dinero` *(Nuevo Sprint 3)* | `EXECUTE` | `EXECUTE` | — |

### Análisis de tablas en AnalisisAlmacenamiento.md

3 Versión







