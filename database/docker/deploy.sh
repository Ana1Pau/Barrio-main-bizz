#!/bin/bash
set -euo pipefail
export PATH=/opt/mssql-tools/bin:$PATH

if [[ ! "${BARRIO_API_DB_PASSWORD:-}" =~ ^[A-Za-z0-9_!-]{32,128}$ ]]; then
  echo "BARRIO_API_DB_PASSWORD must be 32-128 chars using letters, digits, _, -, ! (avoid SQL quoting characters)." >&2
  exit 2
fi

echo "Esperando a que SQL Server acepte conexiones..."
ready=false
for _ in $(seq 1 30); do
  if sqlcmd -S sqlserver -U sa -P "$MSSQL_SA_PASSWORD" -C -Q "SELECT 1" >/dev/null 2>&1; then
    ready=true
    break
  fi
  sleep 5
done
if [[ "$ready" != true ]]; then
  echo "SQL Server no respondió dentro del plazo." >&2
  exit 1
fi

sqlcmd -b -S sqlserver -U sa -P "$MSSQL_SA_PASSWORD" -C -Q "IF DB_ID(N'BarrioDB') IS NULL CREATE DATABASE BarrioDB"
for schema in ident lkp biz catalogo ord pay soc aud app; do
  sqlcmd -b -S sqlserver -U sa -P "$MSSQL_SA_PASSWORD" -C -d BarrioDB -Q "IF SCHEMA_ID(N'$schema') IS NULL EXEC('CREATE SCHEMA $schema AUTHORIZATION dbo')"
done

if ! sqlcmd -b -S sqlserver -U sa -P "$MSSQL_SA_PASSWORD" -C -d BarrioDB -Q "IF OBJECT_ID(N'ident.Usuarios',N'U') IS NOT NULL SELECT 1 ELSE THROW 51000,'BARRIO schema not initialized',1" >/dev/null 2>&1; then
  for file in 01_lkp_catalogos.sql 02_ident_identidad.sql 03_biz_comercios.sql 04_catalogo_productos.sql 05_ord_pedidos.sql 06_pay_pagos.sql 07_soc_comunidad.sql 08_aud_auditoria.sql 09_app_views.sql 10_app_procedures.sql 11_security.sql 12_seed_data.sql; do
    echo "Ejecutando $file..."
    sqlcmd -b -S sqlserver -U sa -P "$MSSQL_SA_PASSWORD" -C -d BarrioDB -i "/scripts/$file"
  done
fi

if ! sqlcmd -b -S sqlserver -U sa -P "$MSSQL_SA_PASSWORD" -C -d BarrioDB -Q "IF OBJECT_ID(N'pay.PeyWebhookInbox',N'U') IS NOT NULL SELECT 1 ELSE THROW 51001,'Pey API migration missing',1" >/dev/null 2>&1; then
  echo "Ejecutando migración 13_api_runtime.sql..."
  sqlcmd -b -S sqlserver -U sa -P "$MSSQL_SA_PASSWORD" -C -d BarrioDB -i /scripts/13_api_runtime.sql
fi

echo "Configurando el principal SQL de la API (acceso limitado al rol role_app_api)..."
sqlcmd -b -S sqlserver -U sa -P "$MSSQL_SA_PASSWORD" -C -d BarrioDB -v ApiPassword="$BARRIO_API_DB_PASSWORD" -i /scripts-entry/create_api_user.sql
echo "BARRIO schema and API principal ready."
