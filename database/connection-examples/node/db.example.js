/**
 * db.example.js
 * Ejemplo de conexion segura a BarrioDB desde Node.js usando el driver
 * "mssql" (tedious). Instalar con:
 *   npm install mssql @azure/identity dotenv
 *
 * Principios de seguridad aplicados:
 *   - encrypt:true, trustServerCertificate:false (TLS obligatorio).
 *   - Autenticacion por defecto via Microsoft Entra ID (Managed Identity en
 *     Azure, o az login en desarrollo) en lugar de usuario/contrasena SQL.
 *   - El modo con contrasena SQL (solo desarrollo local) lee el secreto
 *     EXCLUSIVAMENTE de una variable de entorno (.env no versionado).
 *   - SESSION_CONTEXT se fija por conexion/solicitud para que las
 *     politicas de Row-Level Security funcionen correctamente.
 *   - Todo acceso usa procedimientos almacenados con parametros tipados
 *     (sql.Request().input(...)), nunca concatenacion de strings SQL.
 */

require('dotenv').config();
const sql = require('mssql');
const { DefaultAzureCredential } = require('@azure/identity');

async function getConfig() {
  const authMode = process.env.BARRIO_DB_AUTH_MODE || 'azure-ad';

  const base = {
    server: process.env.BARRIO_DB_SERVER,
    database: process.env.BARRIO_DB_NAME,
    options: {
      encrypt: true,
      trustServerCertificate: false,
    },
    pool: { max: 10, min: 0, idleTimeoutMillis: 30000 },
  };

  if (authMode === 'azure-ad') {
    const credential = new DefaultAzureCredential();
    const tokenResponse = await credential.getToken('https://database.windows.net/.default');
    return {
      ...base,
      authentication: {
        type: 'azure-active-directory-access-token',
        options: { token: tokenResponse.token },
      },
    };
  }

  // Modo de respaldo solo para desarrollo local (nunca en produccion)
  const password = process.env.BARRIO_DB_PASSWORD;
  if (!password) {
    throw new Error(
      'BARRIO_DB_PASSWORD no esta definida. En modo sql-password la contrasena ' +
      'debe venir de una variable de entorno, nunca de codigo fuente versionado.'
    );
  }
  return {
    ...base,
    user: process.env.BARRIO_DB_USER,
    password,
  };
}

let poolPromise;
function getPool() {
  if (!poolPromise) {
    poolPromise = getConfig().then((config) => new sql.ConnectionPool(config).connect());
  }
  return poolPromise;
}

/**
 * Obtiene una conexion con el contexto de sesion (UsuarioId/EsAdmin) fijado
 * para que las politicas de Row-Level Security apliquen correctamente.
 */
async function getRequestForUser(usuarioId, esAdmin = false) {
  const pool = await getPool();
  const request = pool.request();
  await pool.request()
    .input('UsuarioId', sql.UniqueIdentifier, usuarioId || null)
    .input('EsAdmin', sql.Bit, esAdmin)
    .query(`
      EXEC sys.sp_set_session_context @key = N'UsuarioId', @value = @UsuarioId, @read_only = 1;
      EXEC sys.sp_set_session_context @key = N'EsAdmin', @value = @EsAdmin, @read_only = 1;
    `);
  return request;
}

/** Ejemplo: crear un pedido desde el carrito usando el procedimiento almacenado. */
async function crearPedidoDesdeCarrito({ usuarioId, carritoId, metodoEntrega, direccionEntrega, costoEnvio, notaCliente }) {
  const pool = await getPool();
  const result = await pool.request()
    .input('UsuarioId', sql.UniqueIdentifier, usuarioId)
    .input('CarritoId', sql.UniqueIdentifier, carritoId)
    .input('MetodoEntrega', sql.NVarChar(20), metodoEntrega)
    .input('DireccionEntrega', sql.NVarChar(300), direccionEntrega || null)
    .input('CostoEnvio', sql.Decimal(10, 2), costoEnvio || 0)
    .input('NotaCliente', sql.NVarChar(300), notaCliente || null)
    .output('PedidoId', sql.UniqueIdentifier)
    .execute('app.sp_CrearPedidoDesdeCarrito');

  return result.output.PedidoId;
}

module.exports = { getPool, getRequestForUser, crearPedidoDesdeCarrito };
