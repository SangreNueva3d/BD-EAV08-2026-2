# Analisis de tablas
## Supuestos generales y fórmulas de referencia

* **Motor y bloque:** PostgreSQL con tamaño de página $P = B = 8192\text{ bytes}$.
* **Proyección de volumen (Mes 12):** `clientes` ($720$), `cuentas` ($940$), `transacciones` ($860.000\text{/mes}$), `eventos_transaccion` ($2.580.000\text{/mes}$, $3$ por transacción) y `retiros` ($172.000\text{/mes}$, $20\%$ del flujo transaccional).
* **Fórmulas compactas:**
  * **Registro y páginas:** $L = 4\#\text{var} + \sum\text{fijos} + \lceil\frac{\#\text{col}}{8}\rceil + \sum\text{var}_{\text{est}}$, $\quad F_R = \lfloor\frac{P-2}{4+L}\rfloor$, $\quad B_R = \lceil\frac{T_R}{F_R}\rceil$
  * **Índice B-tree:** $F_{R\_\text{idx}} = \lfloor\frac{B}{L_{\text{ent}}}\rfloor$, $\quad d = \lfloor\frac{F_{R\_\text{idx}}+1}{2}\rfloor$, $\quad H \le \log_d V(a,R)$, $\quad \text{Espacio} = B\sum_{k=1}^{H}\lceil\frac{V(a,R)}{d^k}\rceil$

---

## 1. Tabla `clientes` ($T_R = 720$)

### Organización de archivo
Se almacena como **heap** (montón sin orden físico). Es la estrategia más adecuada porque la tabla recibe actualizaciones frecuentes en campos de seguridad y auditoría (`intentos_fallidos`, `bloqueado_hasta`, `fecha_actualizacion`) y se consulta por múltiples llaves candidatas (`id_cliente`, `usuario`, `nit_documento`, `email`); un ordenamiento físico (`CLUSTER`) solo beneficiaría a una llave y penalizaría las escrituras.

### Índices elegidos y estructura

| Índice | Tipo | Justificación |
|---|---|---|
| `clientes_pkey` (`id_cliente`) | B-tree (PK) | Resuelve joins con `cuentas`, `transacciones` y `retiros`, además de la auto-referencia `actualizado_por`. |
| `clientes_usuario_key` (`usuario`) | B-tree (UNIQUE) | Acelera la búsqueda por igualdad en el inicio de sesión (`ClienteService`). |
| `clientes_nit_documento_key` (`nit_documento`) | B-tree (UNIQUE) | Evita duplicados en el registro y permite consulta puntual por documento. |
| `clientes_email_key` (`email`) | B-tree (UNIQUE) | Garantiza unicidad del correo electrónico sin recorridos secuenciales. |

* **Composición (16 columnas):** $6$ fijas (`id_cliente` $16\text{ B}$, `actualizado_por` $16\text{ B}$, `fecha_registro` $8\text{ B}$, `fecha_actualizacion` $8\text{ B}$, `bloqueado_hasta` $8\text{ B}$, `intentos_fallidos` $4\text{ B}$ $\rightarrow 60\text{ B}$) y $10$ variables (`contrasena` hash BCrypt fijo de $60\text{ B}$ + 9 textos estimados en $143\text{ B}$ $\rightarrow 203\text{ B}$).

### Estimación compacta (`clientes_nit_documento_key`, $V = 720$, $L_{\text{ent}} = 20\text{ B}$)
* **Tabla:** $L = 4(10) + 60 + 2 + 203 = 305\text{ B} \implies F_R = \lfloor\frac{8190}{309}\rfloor = 26\text{ reg/pág} \implies B_R = \lceil\frac{720}{26}\rceil = 28\text{ págs}$ ($\approx 224\text{ KB}$).
* **Índice:** $F_{R\_\text{idx}} = \lfloor\frac{8192}{20}\rfloor = 409 \implies d = 205 \implies H = \lceil\log_{205}(720)\rceil = 2$.
* **Nodos y espacio:** $\text{Nodos} = \lceil\frac{720}{205}\rceil + \lceil\frac{720}{205^2}\rceil = 4 + 1 = 5\text{ nodos} \implies \text{Espacio} = 5 \times 8192 = 40\text{ KB}$.

---

## 2. Tabla `cuentas` ($T_R = 940$)

### Organización de archivo
Se almacena como **heap** porque las operaciones del Sprint 3 (depósitos, retiros y transferencias) actualizan constantemente la columna `saldo`, además de los cambios de estado operativo (`bloquearCuenta`). El esquema heap junto con MVCC de PostgreSQL evita reorganizaciones costosas en disco y permite acceder eficientemente tanto por número de cuenta como por titular.

### Índices elegidos y estructura

| Índice | Tipo | Justificación |
|---|---|---|
| `cuentas_pkey` (`id_cuenta`) | B-tree (PK) | Soporte para integridad referencial y bloqueos de fila (`FOR UPDATE`) en procedimientos almacenados. |
| `cuentas_numero_cuenta_key` (`numero_cuenta`) | B-tree (UNIQUE) | Acceso puntual por igualdad (selectividad $100\%$) en consultas de saldo, depósitos, retiros y transferencias. |
| `idx_cuentas_cliente_estado` (`id_cliente, estado`) | B-tree compuesto | Filtra las cuentas activas de un cliente sin escanear toda la tabla (validación de máximo 3 cuentas activas y saldos agregados). |

* **Composición (9 columnas):** $6$ fijas (`id_cuenta` $16\text{ B}$, `id_cliente` $16\text{ B}$, `saldo` $8\text{ B}$, `fecha_vinculacion` $8\text{ B}$, `fecha_actualizacion` $8\text{ B}$, `operaciones_suspendidas` $1\text{ B}$ $\rightarrow 57\text{ B}$) y $3$ variables (`numero_cuenta` $10\text{ B}$, `estado` $8\text{ B}$, `motivo` $2\text{ B}$ $\rightarrow 20\text{ B}$).

### Estimación compacta (`cuentas_numero_cuenta_key`, $V = 940$, $L_{\text{ent}} = 20\text{ B}$)
* **Tabla:** $L = 4(3) + 57 + 2 + 20 = 91\text{ B} \implies F_R = \lfloor\frac{8190}{95}\rfloor = 86\text{ reg/pág} \implies B_R = \lceil\frac{940}{86}\rceil = 11\text{ págs}$ ($\approx 88\text{ KB}$).
* **Índice:** $F_{R\_\text{idx}} = \lfloor\frac{8192}{20}\rfloor = 409 \implies d = 205 \implies H = \lceil\log_{205}(940)\rceil = 2$.
* **Nodos y espacio:** $\text{Nodos} = \lceil\frac{940}{205}\rceil + \lceil\frac{940}{205^2}\rceil = 5 + 1 = 6\text{ nodos} \implies \text{Espacio} = 6 \times 8192 = 48\text{ KB}$.

---

## 3. Tabla `transacciones` ($T_R = 860.000\text{/mes}$)

### Organización de archivo
Se almacena como **heap** con patrón predominantemente *append-only* (inserción continua). Dado que es la tabla transaccional de mayor movimiento monetario, mantenerla sin orden físico evita desplazamientos de bloques en inserciones concurrentes de depósitos, retiros y transferencias.

### Índices elegidos y estructura

| Índice | Tipo | Justificación |
|---|---|---|
| `transacciones_pkey` (`id_transaccion`) | B-tree (PK) | Identificación única de cada operación y enlace con `eventos_transaccion`. |
| `idx_transacciones_origen` (`id_cuenta_origen`) | B-tree | Recupera débitos, retiros y transferencias enviadas desde una cuenta en el estado de cuenta. |
| `idx_transacciones_destino` (`id_cuenta_destino`) | B-tree | Recupera depósitos y transferencias recibidas por una cuenta. |
| `idx_transacciones_cliente` (`id_cliente`) | B-tree | Filtra el historial de operaciones originadas por un cliente específico. |
| `idx_transacciones_fecha` (`fecha_creacion`) | B-tree | Soporta consultas por rango temporal y extractos mensuales sin recorrido completo. |
| `idx_transacciones_estado` (`estado`) | B-tree | Optimiza agregaciones y reportes por estado (`aprobado`, `rechazado`, `reembolsado`). |

* **Composición (10 columnas):** $8$ fijas (`id_transaccion` $16\text{ B}$, `id_cliente` $16\text{ B}$, `id_cuenta_origen` $16\text{ B}$, `id_cuenta_destino` $16\text{ B}$, `monto` $8\text{ B}$, `fecha_creacion` $8\text{ B}$, `fecha_actualizacion` $8\text{ B}$, `moneda` $3\text{ B}$ $\rightarrow 91\text{ B}$) y $2$ variables (`estado` $8\text{ B}$, `referencia_externa` $12\text{ B}$ $\rightarrow 20\text{ B}$).

### Estimación compacta (`idx_transacciones_fecha`, $V = 860.000$, $L_{\text{ent}} = 16\text{ B}$)
* **Tabla:** $L = 4(2) + 91 + 2 + 20 = 121\text{ B} \implies F_R = \lfloor\frac{8190}{125}\rfloor = 65\text{ reg/pág} \implies B_R = \lceil\frac{860.000}{65}\rceil = 13.231\text{ págs}$ ($\approx 103,37\text{ MB}$).
* **Índice:** $F_{R\_\text{idx}} = \lfloor\frac{8192}{16}\rfloor = 512 \implies d = 256 \implies H = \lceil\log_{256}(860.000)\rceil = 3$.
* **Nodos y espacio:** $\text{Nodos} = \lceil\frac{860.000}{256}\rceil + \lceil\frac{860.000}{256^2}\rceil + 1 = 3.360 + 14 + 1 = 3.375\text{ nodos} \implies \text{Espacio} = 3.375 \times 8192 \approx 26,37\text{ MB}$.

---

## 4. Tabla `eventos_transaccion` ($T_R = 2.580.000\text{/mes}$)

### Organización de archivo
Se almacena como **heap** estrictamente inmutable (`INSERT`-only, con `UPDATE` y `DELETE` revocados a la aplicación). Como registra cada evento de auditoría (depósito, retiro, transferencia y cambios de estado), el almacenamiento secuencial al final del archivo elimina por completo la fragmentación por actualizaciones.

### Índices elegidos y estructura

| Índice | Tipo | Justificación |
|---|---|---|
| `eventos_transaccion_pkey` (`id_evento`) | B-tree (PK) | Llave primaria autoincremental (`IDENTITY`) con inserciones ordenadas en el extremo derecho del árbol. |
| `idx_eventos_transaccion_id` (`id_transaccion, fecha_evento`) | B-tree compuesto | Permite reconstruir la trazabilidad cronológica completa de una transacción en una sola lectura de rango. |

* **Composición (7 columnas):** $3$ fijas (`id_transaccion` $16\text{ B}$, `id_evento` $8\text{ B}$, `fecha_evento` $8\text{ B}$ $\rightarrow 32\text{ B}$) y $4$ variables (`tipo_evento` $12\text{ B}$, `estado_anterior` $4\text{ B}$, `estado_nuevo` $8\text{ B}$, `detalle` $35\text{ B}$ $\rightarrow 59\text{ B}$).

### Estimación compacta (`idx_eventos_transaccion_id`, $V = 2.580.000$, $L_{\text{ent}} = 32\text{ B}$)
* **Tabla:** $L = 4(4) + 32 + 1 + 59 = 108\text{ B} \implies F_R = \lfloor\frac{8190}{112}\rfloor = 73\text{ reg/pág} \implies B_R = \lceil\frac{2.580.000}{73}\rceil = 35.343\text{ págs}$ ($\approx 276,12\text{ MB}$).
* **Índice:** $F_{R\_\text{idx}} = \lfloor\frac{8192}{32}\rfloor = 256 \implies d = 128 \implies H = \lceil\log_{128}(2.580.000)\rceil = 4$.
* **Nodos y espacio:** $\text{Nodos} = \lceil\frac{2.580.000}{128}\rceil + \lceil\frac{2.580.000}{128^2}\rceil + \lceil\frac{2.580.000}{128^3}\rceil + 1 = 20.157 + 158 + 2 + 1 = 20.318\text{ nodos} \implies \text{Espacio} \approx 158,73\text{ MB}$.

---

## 5. Tabla `retiros` ($T_R = 172.000\text{/mes}$)

### Organización de archivo
Se almacena como **heap** de registros inmutables y de longitud fija ($0$ columnas variables). Esto garantiza un empaquetamiento máximo por bloque sin desperdicio por descriptores variables ni reubicación de tuplas tras la inserción del retiro.

### Índices elegidos y estructura

| Índice | Tipo | Justificación |
|---|---|---|
| `retiros_pkey` (`id_retiro`) | B-tree (PK) | Identificador único del comprobante de retiro. |
| `idx_retiros_cuenta` (`id_cuenta, fecha`) | B-tree compuesto | Consulta rápida del historial de retiros efectuados sobre una cuenta ordenados por fecha. |
| `idx_retiros_cliente` (`id_cliente, fecha`) | B-tree compuesto | Audita todos los retiros realizados por un cliente sobre sus cuentas propias. |

* **Composición (5 columnas):** $5$ fijas (`id_retiro` $16\text{ B}$, `id_cliente` $16\text{ B}$, `id_cuenta` $16\text{ B}$, `monto` $8\text{ B}$, `fecha` $8\text{ B}$ $\rightarrow 64\text{ B}$) y $0$ variables.

### Estimación compacta (`idx_retiros_cuenta`, $V = 172.000$, $L_{\text{ent}} = 32\text{ B}$)
* **Tabla:** $L = 0 + 64 + 1 + 0 = 65\text{ B} \implies F_R = \lfloor\frac{8190}{69}\rfloor = 118\text{ reg/pág} \implies B_R = \lceil\frac{172.000}{118}\rceil = 1.458\text{ págs}$ ($\approx 11,39\text{ MB}$).
* **Índice:** $F_{R\_\text{idx}} = \lfloor\frac{8192}{32}\rfloor = 256 \implies d = 128 \implies H = \lceil\log_{128}(172.000)\rceil = 3$.
* **Nodos y espacio:** $\text{Nodos} = \lceil\frac{172.000}{128}\rceil + \lceil\frac{172.000}{128^2}\rceil + 1 = 1.344 + 11 + 1 = 1.356\text{ nodos} \implies \text{Espacio} \approx 10,59\text{ MB}$.

---

## Resumen comparativo (Proyección Mes 12)

| Tabla | $T_R$ | $L$ | $F_R$ | $B_R$ | Tamaño tabla | Índice evaluado | $d$ | $H$ | Tamaño índice |
|---|---|---|---|---|---|---|---|---|---|
| `clientes` | $720$ | $305\text{ B}$ | $26$ | $28$ | $224\text{ KB}$ | `clientes_nit_documento_key` | $205$ | $2$ | $40\text{ KB}$ |
| `cuentas` | $940$ | $91\text{ B}$ | $86$ | $11$ | $88\text{ KB}$ | `cuentas_numero_cuenta_key` | $205$ | $2$ | $48\text{ KB}$ |
| `transacciones` | $860.000$ | $121\text{ B}$ | $65$ | $13.231$ | $103,37\text{ MB}$ | `idx_transacciones_fecha` | $256$ | $3$ | $26,37\text{ MB}$ |
| `eventos_transaccion` | $2.580.000$ | $108\text{ B}$ | $73$ | $35.343$ | $276,12\text{ MB}$ | `idx_eventos_transaccion_id` | $128$ | $4$ | $158,73\text{ MB}$ |
| `retiros` | $172.000$ | $65\text{ B}$ | $118$ | $1.458$ | $11,39\text{ MB}$ | `idx_retiros_cuenta` | $128$ | $3$ | $10,59\text{ MB}$ |

# Analisis hecho con Claude y revisadas las formulas con calculadora, todas están bien
