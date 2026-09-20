# BD-EAV08-2026-2
Repositorio para entregables propios de la materia de Bases de datos y laboratorios del equipo avanzado 8 de la edición 26-2 de CodeF@ctory, equipo conformado por:

YEPES JARAMILLO ANGEL SIMON: angel.yepes2@udea.edu.co
FORERO AGUDELO CARLOS ALBERTO: carlos.forero@udea.edu.co
ALBORNOZ VILLADIEGO JOSÉ FERNANDO: jose.albornoz@udea.edu.co
CONTRERAS PUELLO SAMUEL ESTEBAN: samuel.contreras@udea.edu.co

#Criterio 1- Entidades y Relaciones
### Diagrama Entidad Relación Mermaid

```mermaid
erDiagram
    CLIENTES ||--o{ CUENTAS_BANCARIAS : posee
    CLIENTES ||--o{ CREDENCIALES_API : genera
    CLIENTES ||--o{ TRANSACCIONES : origina
    CLIENTES ||--o{ REPORTES : solicita
    CUENTAS_BANCARIAS ||--o{ TRANSACCIONES : "cuenta origen"
    CUENTAS_BANCARIAS ||--o{ TRANSACCIONES : "cuenta destino"
    TRANSACCIONES ||--o{ EVENTOS_TRANSACCION : registra

    CLIENTES {
        uuid id_cliente PK
        varchar nombre_comercial
        varchar razon_social
        varchar nit_documento UK
        varchar email UK
        varchar telefono
        varchar estado
        timestamptz fecha_registro
    }

    CUENTAS_BANCARIAS {
        uuid id_cuenta PK
        uuid id_cliente FK
        varchar numero_cuenta
        varchar banco
        varchar tipo_cuenta
        char moneda
        varchar estado
        timestamptz fecha_vinculacion
    }

    CREDENCIALES_API {
        uuid id_credencial PK
        uuid id_cliente FK
        varchar api_key UK
        varchar api_secret_hash
        varchar ambiente
        varchar estado
        timestamptz fecha_creacion
        timestamptz fecha_expiracion
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

    REPORTES {
        uuid id_reporte PK
        uuid id_cliente FK
        varchar tipo_reporte
        date periodo_inicio
        date periodo_fin
        timestamptz fecha_generacion
        jsonb contenido
    }
```

