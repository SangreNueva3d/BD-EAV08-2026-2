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

### Consulta analizada

Responde la pregunta clave 8 del README ("¿cuál es el saldo total agregado por comercio,
sumando sus cuentas activas?"):

```sql
SELECT c.nombre_comercial, SUM(cu.saldo) AS saldo_total
FROM clientes c
JOIN cuentas cu ON cu.id_cliente = c.id_cliente
WHERE cu.estado = 'activo'
GROUP BY c.nombre_comercial;
```

### Estadísticas usadas y su origen

`cuentas` ya se calculó en el criterio 7. Para `clientes` se repite el mismo método 

| Columna | Clasificación | Tamaño |
|---|---|---|
| `id_cliente` | Fijo | 16 |
| `fecha_registro` | Fijo | 8 |
| `actualizado_por` | Fijo | 16 |
| `fecha_actualizacion` | Fijo | 8 |
| `intentos_fallidos` | Fijo | 4 |
| `bloqueado_hasta` | Fijo | 8 |
| `nombre_comercial`, `razon_social`, `nit_documento`, `email`, `usuario`, `contrasena`, `telefono`, `estado`, `rol`, `motivo` | Variables (10 campos) | 25+35+12+28+15+60+10+7+8+3 = 203 |

`contrasena` se estima en 60 bytes exactos porque BCrypt produce hashes de longitud fija
(60 caracteres), no un valor arbitrario.

```
Σ fijos = 16+8+16+8+4+8 = 60 bytes
4·#var = 4·10 = 40 bytes
mapa de bits = ⌈16 columnas / 8⌉ = 2 bytes
L_clientes = 40 + 60 + 2 + 203 = 305 bytes

FR_clientes = ⌊(8192−2)/(4+305)⌋ = ⌊8190/309⌋ = 26 registros/página
BR_clientes = ⌈720 / 26⌉ = 28 páginas   (TR=720, proyección a 12 meses, sección 5 del README)
```

Resumen de estadísticas para el join:

| Relación | TR (tuplas) | BR (páginas) |
|---|---|---|
| `clientes` (R) | 720 | 28 |
| `cuentas` (S) | 940 | 11 |

Memoria disponible asumida: **M = 15 páginas** (buffer modesto, razonable para un servicio
desplegado en el plan gratuito de Render, que comparte recursos con otros procesos).

### Fórmula aplicada y por qué

El predicado de unión (`id_cliente`) no es selectivo por sí solo (no hay filtro de igualdad
sobre un valor puntual), así que se evalúan las tres estrategias de reunión de la rúbrica para
elegir la más barata: **nested-loop por bloques**, **nested-loop indexado** y **hash join**.

**1) Nested-loop por bloques** — `Costo = BR + BS · ⌈BR/(M−2)⌉` (conviene poner como relación
externa la más pequeña en páginas):

```
cuentas como externa:  BS + BR·⌈BS/(M−2)⌉ = 11 + 28·⌈11/13⌉ = 11 + 28·1 = 39 páginas
clientes como externa: BR + BS·⌈BR/(M−2)⌉ = 28 + 11·⌈28/13⌉ = 28 + 11·3 = 61 páginas
```

Poner `cuentas` (la relación más pequeña) como externa reduce el costo de 61 a 39 páginas.

**2) Nested-loop indexado** — `Costo = BT + TT · S(b,R)`, usando `cuentas` como relación
externa (BT=11, TT=940) y sondeando el índice de la **clave primaria** de `clientes`:

```
S(id_cliente, clientes) = TR_clientes / V(id_cliente,clientes) = 720/720 = 1
Costo = 11 + 940·1 = 951 páginas
```

Sale caro porque el costo de este método depende del número de **tuplas** de la relación
externa (940), no de sus páginas — y `cuentas` es una tabla "densa" (86 registros/página), así
que hay muchas sondas de índice redundantes.

**3) Hash join (en memoria)** — `Costo = BR + BS` (válido porque M=15 páginas alcanza para
construir la tabla hash de la relación más pequeña, `cuentas`, con 11 páginas):

```
Costo = 28 + 11 = 39 páginas
```

### Comparación y conclusión

| Estrategia | Costo (páginas de E/S) |
|---|---|
| Nested-loop por bloques (`cuentas` externa) | 39 |
| Nested-loop por bloques (`clientes` externa) | 61 |
| Nested-loop indexado | 951 |
| **Hash join** | **39** |

El **hash join es la elección recomendada**: su costo no depende de cómo se ordene R y S, es
estable frente al crecimiento de ambas tablas, y es, de hecho, la estrategia que el planificador
de PostgreSQL elegiría en la práctica para una reunión por igualdad sin un filtro selectivo de
por medio.



# Criterio 9 — Optimización algebraica de la misma consulta

### SQL original

```sql
SELECT c.nombre_comercial, SUM(cu.saldo) AS saldo_total
FROM clientes c
JOIN cuentas cu ON cu.id_cliente = c.id_cliente
WHERE cu.estado = 'activo'
GROUP BY c.nombre_comercial;
```

### Expresión algebraica inicial (traducción literal del SQL)

```
γ nombre_comercial; SUM(saldo)→saldo_total (
    σ estado='activo' (
        clientes ⋈ id_cliente=id_cliente cuentas
    )
)
```

Tal como está escrita, la selección se aplica **después** de reunir las 720 filas de `clientes`
con las 940 de `cuentas` — el join procesa cuentas que luego se van a descartar.

### Transformación 1 — Ley 4/5 (selección sobre una reunión)

`σp(E1 ⋈ E2) ≡ σp1(E1) ⋈ σp2(E2)`, si p1 usa solo atributos de E1 y p2 solo de E2.

El predicado `estado='activo'` usa exclusivamente un atributo de `cuentas`, así que se empuja
directo sobre esa relación, antes del join (heurística general: aplicar selecciones lo antes
posible, hacia las hojas del árbol):

```
σ estado='activo' (clientes ⋈ cuentas)  ≡  clientes ⋈ σ estado='activo' (cuentas)
```

### Transformación 2 — Ley 9 (proyección sobre una reunión)

`πx,y(E1 ⋈ E2) ≡ πx(E1) ⋈ πy(E2)`, si x ⊆ atributos(E1) y y ⊆ atributos(E2).

La agregación solo necesita `nombre_comercial` de `clientes` y `saldo` de `cuentas` (más la
clave de unión `id_cliente` en ambas, para poder reconstruir el join). Se proyecta cada relación
a esas columnas antes de unir:

```
π nombre_comercial, id_cliente (clientes)  ⋈  π id_cliente, saldo (σ estado='activo' (cuentas))
```

### Expresión optimizada final

```
γ nombre_comercial; SUM(saldo)→saldo_total (
    π nombre_comercial, id_cliente (clientes)
    ⋈ id_cliente=id_cliente
    π id_cliente, saldo (σ estado='activo' (cuentas))
)
```

### Por qué es más barata — tuplas intermedias antes y después

- **Antes de optimizar:** el join combina 940 cuentas (todas, sin filtrar) con sus clientes,
  arrastrando las 16 columnas de `clientes` (incluida `contrasena`, de 60 bytes) y las 9 de
  `cuentas` en cada tupla intermedia. Tamaño aproximado por tupla intermedia: `L_clientes +
  L_cuentas = 305 + 91 = 396 bytes`. Total: `940 × 396 ≈ 372.240 bytes` antes de poder aplicar
  el filtro y la agregación.
- **Después de optimizar:** la selección reduce `cuentas` a solo las filas con `estado='activo'`
  (≈ 85% del total en un sistema sano ≈ 800 filas) **antes** del join, y la proyección descarta
  todo lo que no sea `id_cliente`, `nombre_comercial` o `saldo` — cada tupla intermedia pesa
  apenas `16+25 ≈ 41 bytes` (lado clientes) u `16+8 = 24 bytes` (lado cuentas), en vez de 396.
  Total aproximado: `800 × 24 ≈ 19.200 bytes` del lado de `cuentas`, un **~95% menos de datos**
  movidos hacia la operación de join.

  
```sql
SELECT c.nombre_comercial, SUM(cu.saldo) AS saldo_total
FROM (SELECT id_cliente, nombre_comercial FROM clientes) AS c
JOIN (SELECT id_cliente, saldo FROM cuentas WHERE estado = 'activo') AS cu
  ON cu.id_cliente = c.id_cliente
GROUP BY c.nombre_comercial;
```

El join optimizado procesa menos filas (las inactivas nunca llegan a unirse) y tuplas mucho más
angostas (sin arrastrar columnas que la consulta no necesita) — menos I/O, menos comparaciones
de join y menos memoria ocupada en cada paso.
