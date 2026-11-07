// DbConnectionFactory.cs
// Ejemplo de fabrica de conexiones seguras a BarrioDB para una API .NET.
//
// Paquetes NuGet necesarios:
//   Microsoft.Data.SqlClient
//   Azure.Identity
//
// Principios de seguridad aplicados:
//   - Encrypt=True y TrustServerCertificate=False siempre (TLS obligatorio).
//   - Autenticacion por defecto via Microsoft Entra ID (Managed Identity en
//     Azure App Service/Functions, o `az login` en desarrollo local) en vez
//     de usuario/contrasena SQL embebidos en el codigo o en appsettings.
//   - La contrasena SQL (solo para el modo de respaldo SqlPassword) jamas
//     se lee de un archivo de configuracion: se toma de una variable de
//     entorno que el pipeline/orquestador inyecta desde Key Vault.
//   - Column Encryption Setting=Enabled para que el driver desencripte de
//     forma transparente las columnas protegidas con Always Encrypted
//     (p.ej. pay.Pagos.TokenPagoEncriptado).
//   - SESSION_CONTEXT se fija en cada conexion para que las politicas de
//     Row-Level Security (seg.PedidosAccesoPolicy) filtren correctamente.

using System;
using Azure.Identity;
using Microsoft.Data.SqlClient;

namespace Barrio.Data;

public sealed class BarrioDbOptions
{
    public string Server { get; set; } = string.Empty;
    public string Database { get; set; } = string.Empty;
    public string AuthMode { get; set; } = "AzureAD_Default";
    public string? UserId { get; set; }
    public string? PasswordEnvVar { get; set; }
}

public sealed class DbConnectionFactory
{
    private readonly BarrioDbOptions _options;

    public DbConnectionFactory(BarrioDbOptions options) => _options = options;

    private string BuildBaseConnectionString()
    {
        var builder = new SqlConnectionStringBuilder
        {
            DataSource = _options.Server,
            InitialCatalog = _options.Database,
            Encrypt = true,
            TrustServerCertificate = false,
            ColumnEncryptionSetting = SqlConnectionColumnEncryptionSetting.Enabled,
            ConnectTimeout = 30
        };
        return builder.ConnectionString;
    }

    /// <summary>Abre una conexion autenticada y lista para usarse.</summary>
    public SqlConnection CreateOpenConnection(Guid? usuarioAutenticadoId = null, bool esAdmin = false)
    {
        SqlConnection connection = _options.AuthMode switch
        {
            "AzureAD_Default" => CreateWithManagedIdentity(),
            "AzureAD_ServicePrincipal" => CreateWithManagedIdentity(),
            "SqlPassword" => CreateWithSqlPassword(),
            _ => throw new InvalidOperationException($"AuthMode no soportado: {_options.AuthMode}")
        };

        connection.Open();
        SetSessionContext(connection, usuarioAutenticadoId, esAdmin);
        return connection;
    }

    private SqlConnection CreateWithManagedIdentity()
    {
        // DefaultAzureCredential intenta, en orden: Managed Identity (en Azure),
        // Visual Studio/CLI login (en desarrollo), variables de entorno, etc.
        // Nunca se escribe un secreto en el codigo.
        var credential = new DefaultAzureCredential();
        var connection = new SqlConnection(BuildBaseConnectionString());
        connection.AccessTokenCallback = async (authParams, cancellationToken) =>
        {
            var token = await credential.GetTokenAsync(
                new Azure.Core.TokenRequestContext(new[] { "https://database.windows.net/.default" }),
                cancellationToken);
            return new SqlAuthenticationToken(token.Token, token.ExpiresOn);
        };
        return connection;
    }

    private SqlConnection CreateWithSqlPassword()
    {
        if (string.IsNullOrWhiteSpace(_options.PasswordEnvVar))
            throw new InvalidOperationException("PasswordEnvVar no esta configurado.");

        var password = Environment.GetEnvironmentVariable(_options.PasswordEnvVar)
            ?? throw new InvalidOperationException(
                $"La variable de entorno '{_options.PasswordEnvVar}' no esta definida. " +
                "La contrasena debe inyectarse en tiempo de ejecucion, nunca guardarse en el repositorio.");

        var builder = new SqlConnectionStringBuilder(BuildBaseConnectionString())
        {
            UserID = _options.UserId,
            Password = password
        };
        return new SqlConnection(builder.ConnectionString);
    }

    private static void SetSessionContext(SqlConnection connection, Guid? usuarioId, bool esAdmin)
    {
        using var cmd = connection.CreateCommand();
        cmd.CommandText = "EXEC sys.sp_set_session_context @key = N'UsuarioId', @value = @UsuarioId, @read_only = 1; " +
                           "EXEC sys.sp_set_session_context @key = N'EsAdmin', @value = @EsAdmin, @read_only = 1;";
        cmd.Parameters.AddWithValue("@UsuarioId", (object?)usuarioId ?? DBNull.Value);
        cmd.Parameters.AddWithValue("@EsAdmin", esAdmin);
        cmd.ExecuteNonQuery();
    }
}
