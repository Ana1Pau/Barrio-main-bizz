const required = (name, value) => {
  if (!value) throw new Error(`${name} is required`);
  return value;
};

export function loadConfig(env = process.env) {
  const nodeEnv = env.NODE_ENV || 'development';
  const authMode = env.BARRIO_DB_AUTH_MODE || (nodeEnv === 'production' ? 'azure-managed-identity' : 'sql-password');
  const paymentMode = env.PAYMENTS_MODE || 'simulated';
  const liveChargesEnabled = env.PEY_LIVE_CHARGES_ENABLED === 'true';
  if (!['sql-password', 'azure-managed-identity'].includes(authMode)) throw new Error('Unsupported BARRIO_DB_AUTH_MODE');
  if (!['simulated', 'pey'].includes(paymentMode)) throw new Error('PAYMENTS_MODE must be simulated or pey');
  if (nodeEnv === 'production' && authMode === 'sql-password' && env.BARRIO_ALLOW_SQL_PASSWORD_AUTH !== 'true') throw new Error('Production requires managed identity for SQL unless the explicit local-container override is enabled');
  if (nodeEnv === 'production' && paymentMode === 'simulated') {
    // Simulation is deliberately allowed in production deployments until owners enable live payments.
  }
  const jwtSecret = required('JWT_SECRET', env.JWT_SECRET);
  if (Buffer.byteLength(jwtSecret) < 32) throw new Error('JWT_SECRET must contain at least 32 bytes');
  if (paymentMode === 'pey') {
    if (nodeEnv !== 'production' || !liveChargesEnabled) throw new Error('Live Pey requests require production and PEY_LIVE_CHARGES_ENABLED=true');
    required('PEY_API_KEY', env.PEY_API_KEY);
    required('PEY_WEBHOOK_SECRET', env.PEY_WEBHOOK_SECRET);
  }
  return {
    nodeEnv,
    port: Number(env.PORT || 8080),
    corsOrigins: (env.CORS_ORIGINS || 'http://localhost:4176').split(',').map((x) => x.trim()).filter(Boolean),
    jwtSecret,
    db: {
      server: required('BARRIO_DB_SERVER', env.BARRIO_DB_SERVER),
      database: required('BARRIO_DB_NAME', env.BARRIO_DB_NAME),
      authMode,
      clientId: env.AZURE_CLIENT_ID,
      user: env.BARRIO_DB_USER,
      password: env.BARRIO_DB_PASSWORD,
    },
    paymentMode,
    peyApiKey: env.PEY_API_KEY,
    peyWebhookSecret: env.PEY_WEBHOOK_SECRET,
    webhookToleranceSeconds: Number(env.PEY_WEBHOOK_TOLERANCE_SECONDS || 300),
  };
}
