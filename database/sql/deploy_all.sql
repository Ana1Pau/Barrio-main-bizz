/* ============================================================================
   deploy_all.sql
   Orquesta la ejecucion de todos los scripts en orden. Pensado para usarse
   con sqlcmd (soporta :r para incluir archivos) o como referencia del orden
   a seguir en Azure Data Studio / SSMS / pipelines de CI-CD.

   Uso con sqlcmd:
     sqlcmd -S <servidor>.database.windows.net -d BarrioDB -G -i deploy_all.sql
   (-G fuerza autenticacion con Azure AD / Microsoft Entra ID)
============================================================================ */

:r 00_create_database.sql
:r 01_lkp_catalogos.sql
:r 02_ident_identidad.sql
:r 03_biz_comercios.sql
:r 04_catalogo_productos.sql
:r 05_ord_pedidos.sql
:r 06_pay_pagos.sql
:r 07_soc_comunidad.sql
:r 08_aud_auditoria.sql
:r 09_app_views.sql
:r 10_app_procedures.sql
:r 11_security.sql
:r 12_seed_data.sql
:r 13_api_runtime.sql
