Supuesto general: tamaño de página `P = 8192 bytes` (el valor por defecto de PostgreSQL, el
motor real del proyecto).
# Criterio 7 — Estrategia de almacenamiento e índices (tabla `cuentas`)

###  Organización de archivo

`cuentas` se almacena como **heap** (montón, sin orden físico), que es la organización por
defecto de PostgreSQL — no se usa `CLUSTER` sobre ninguna clave. Se justifica así porque la
tabla se consulta sobre todo por dos vías distintas (`numero_cuenta` para operaciones puntuales,
`id_cliente` para listar las cuentas de un comercio), y una organización clúster solo favorece
una de las dos; es más flexible resolver ambos accesos con índices secundarios sobre un heap.

###  Índices elegidos

| Índice | Tipo | Justificación |
|---|---|---|
| `numero_cuenta` (UNIQUE) | B-tree, creado automáticamente por la restricción `UNIQUE` | Es el valor con el que el comercio consulta el estado de una cuenta puntual (`CuentaController`) — acceso por igualdad, selectivo al 100% (clave candidata) |
| `idx_cuentas_cliente_estado` (`id_cliente, estado`) | B-tree compuesto | Resuelve "todas las cuentas activas de un comercio" (pregunta clave 8 del README) sin recorrer toda la tabla |

La estimación cuantitativa completa (L, FR, BR y el árbol del índice) se desarrolla sobre
`numero_cuenta`, por ser un caso más simple de ilustrar (clave candidata de un solo atributo).

###  Estimación del tamaño de un registro (L)

Columnas de `cuentas` (9 en total) clasificadas por tipo:

| Columna | Tipo | Clasificación | Tamaño |
|---|---|---|---|
| `id_cuenta` | uuid | Fijo | 16 bytes |
| `id_cliente` | uuid | Fijo | 16 bytes |
| `numero_cuenta` | varchar(20) | Variable | ~10 bytes (contenido real: 10 dígitos, ver `GeneradorNumeroCuenta`) |
| `estado` | varchar(30) | Variable | ~8 bytes (promedio entre `'activo'`, `'inactivo'`, `'bloqueado'`) |
| `saldo` | numeric(19,2) | Fijo | 8 bytes |
| `motivo` | varchar(200) | Variable | ~2 bytes (nulo en la gran mayoría de las filas: solo se llena si la cuenta se bloquea o suspende) |
| `operaciones_suspendidas` | boolean | Fijo | 1 byte |
| `fecha_vinculacion` | timestamptz | Fijo | 8 bytes |
| `fecha_actualizacion` | timestamptz | Fijo | 8 bytes |

- Σ tamaño(campos fijos) = 16+16+8+1+8+8 = **57 bytes**
- #campos variables = 3 (`numero_cuenta`, `estado`, `motivo`) → 4·3 = **12 bytes** (descriptores de posición/longitud)
- Σ tamaño estimado(campos variables) = 10+8+2 = **20 bytes**
- Tamaño del mapa de bits (nulabilidad) = ⌈9 columnas / 8⌉ = **2 bytes**

```
L = 4·#var + Σ fijos + mapa_bits + Σ var_estimado
L = 12 + 57 + 2 + 20 = 91 bytes
```

###  Registros por página (FR) y páginas de la tabla (BR)

```
P = 2 + 4·FR + FR·L  →  FR = ⌊(P − 2) / (4 + L)⌋
FR = ⌊(8192 − 2) / (4 + 91)⌋ = ⌊8190 / 95⌋ = 86 registros/página
```

Usando la estimación de volumen de la sección 5 del README (`TR` inicial = 390, proyectado a 12
meses = 940):

```
BR = ⌈TR / FR⌉
BR_inicial = ⌈390 / 86⌉ = 5 páginas
BR_12 meses = ⌈940 / 86⌉ = 11 páginas
```

`cuentas` es una tabla compacta: incluso a 12 meses, un recorrido secuencial completo tocaría
solo 11 páginas. Igual se justifica el índice por el patrón de acceso (búsquedas puntuales
frecuentes), no por el tamaño de la tabla.

###  Estimación del índice sobre `numero_cuenta`

Tamaño de una entrada del índice: clave (~10 dígitos + overhead ≈ 12 bytes) + puntero a la fila
(≈ 8 bytes) = **L_entrada ≈ 20 bytes**.

```
FR_índice = ⌊B / L_entrada⌋ = ⌊8192 / 20⌋ = 409 entradas/nodo
2d − 1 = FR_índice  →  d = (409 + 1) / 2 = 205   (cumple d ≥ 3)
```

**Altura (H):** como `numero_cuenta` es clave candidata, `V(numero_cuenta, cuentas) = TR = 940`
(a 12 meses, todas distintas).

```
H ≤ log_d V(a,R) = log_205(940) ≈ 1.29  →  H = 2 (raíz + hojas)
```

**Nodos por nivel** (fórmula de referencia: `nodos del nivel k ≈ V(a,R) / d^k`, contando k=1 en
las hojas hasta k=H en la raíz):

```
Nivel 1 (hojas): V / d^1 = 940 / 205 ≈ 4.59  →  5 nodos
Nivel 2 (raíz):  V / d^2 = 940 / 205² ≈ 0.02 →  1 nodo
Total: 5 + 1 = 6 nodos
```

**Espacio del índice:**

```
Espacio = nodos_totales × B = 6 × 8192 = 49.152 bytes ≈ 48 KB
```

Un índice de solo 2 niveles y 48 KB para resolver cualquier búsqueda por `numero_cuenta` en una
sola lectura de hoja (más la raíz, que normalmente queda cacheada en memoria) — justifica
sobradamente su costo de mantenimiento frente al beneficio en las operaciones de consulta de
saldo, que son las más frecuentes del sistema.

---


# Criterio 8 — Costo de una consulta con reunión (join)


# Criterio 9 — Optimización algebraica de la misma consulta

