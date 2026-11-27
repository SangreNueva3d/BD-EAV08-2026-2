# Retroalimentación – Bases de Datos

Calificación por sprint según la rúbrica de cada entrega. Los scripts se ejecutaron en PostgreSQL 16 vacío. Lo que venía de un sprint anterior aparece como sugerencia y no descuenta.

## Sprint 1 — 4.8 / 5.0

| Criterio | Nivel | Puntos |
|---|---|---|
| C1 Entidades y relaciones | Excelente | 1.25 / 1.25 |
| C2 Preguntas clave | Excelente | 0.75 / 0.75 |
| C3 Modelo lógico | Excelente | 1.00 / 1.00 |
| C4 Modelo físico | Excelente | 1.25 / 1.25 |
| C5 Repositorio y documentación | Aceptable | 0.55 / 0.75 |

- C1: bien resuelto el doble rol cuenta origen / cuenta destino.
- C4: corre sin errores. `IS DISTINCT FROM` en el CHECK de origen ≠ destino es correcto con nulos.
- C5: todos los commits en un solo día y desde una sola cuenta. Dos mensajes "Add files via upload".
- Sugerencias: CHECK o catálogo para `moneda`; archivo `.sql` con las consultas.

## Sprint 2 — 4.4 / 5.0

| Criterio | Nivel | Puntos |
|---|---|---|
| C1 MER refinado | Aceptable | 0.45 / 0.60 |
| C2 Modelo físico | Excelente | 0.80 / 0.80 |
| C3 schema.sql | Excelente | 0.80 / 0.80 |
| C4 Consultas | Excelente | 0.70 / 0.70 |
| C5 Volumen | Excelente | 0.50 / 0.50 |
| C6 Roles y seguridad | Insuficiente | 0.25 / 0.60 |
| C7 Almacenamiento e índices | Aceptable | 0.30 / 0.40 |
| C8 Costo de una consulta | Excelente | 0.30 / 0.30 |
| C9 Optimización algebraica | Excelente | 0.30 / 0.30 |

- C1: `actualizado_por` (nueva en este sprint) admite nulo, pero el MER la dibuja obligatoria (`||` en vez de `|o`).
- C6: hay matriz de roles, pero ningún `CREATE ROLE` / `GRANT` / `REVOKE` en el repo; la base queda sin roles.
- C7: se analizó `cuentas` (940 filas); la tabla relevante es `transacciones`. `numeric` no es de 8 bytes fijos. El archivo va en `docs/analisis-almacenamiento.md`.

## Sprint 3 — 4.7 / 5.0

| Criterio | Nivel | Puntos |
|---|---|---|
| C1 MER refinado | Excelente | 0.70 / 0.70 |
| C2 Script refinado | Excelente | 0.80 / 0.80 |
| C3 Triggers | Excelente | 1.10 / 1.10 |
| C4 Procedimientos | Excelente | 1.10 / 1.10 |
| C5 Consultas | Aceptable | 0.45 / 0.60 |
| C6 Roles y seguridad | Aceptable | 0.50 / 0.70 |

- C3/C4: los 5 triggers y los 3 procedimientos funcionan como `rol_app`. Buen uso de `FOR UPDATE` en orden de `id_cuenta` para evitar interbloqueos.
- C4: los procedimientos no devuelven nada (sugerencia: `OUT` con el id de la transacción). Los ejemplos no corren sin seed.
- C5: de las 10 consultas del Sprint 2 quedan 5; solo se justifica la de `credenciales_api`.
- C6: `rol_app` puede hacer `UPDATE cuentas SET saldo = ...` e insertar en `retiros` sin pasar por los procedimientos. `eventos_transaccion` queda sin RLS.
- C2: `retiros` no tiene FK a su transacción; un `INSERT` directo en `retiros` no descuenta saldo.
- Sugerencias: en el MER, `id_cuenta_origen`, `id_cuenta_destino` y `actualizado_por` deberían ser `|o`; quitar a `rol_lectura` el acceso a `contrasena`.
- Repositorio: los 5 commits del sprint en 11 minutos. La rúbrica pide commits incrementales.

## Nota final: 4.6

Promedio simple de los tres sprints.
