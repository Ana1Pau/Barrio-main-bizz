IF SUSER_ID(N'barrio_app_api') IS NULL
BEGIN
  CREATE LOGIN barrio_app_api WITH PASSWORD=N'$(ApiPassword)', CHECK_POLICY=ON, CHECK_EXPIRATION=OFF;
END;
GO
IF DATABASE_PRINCIPAL_ID(N'barrio_app_api') IS NULL
  CREATE USER barrio_app_api FOR LOGIN barrio_app_api;
GO
IF NOT EXISTS (
  SELECT 1 FROM sys.database_role_members rm
  JOIN sys.database_principals rolep ON rolep.principal_id=rm.role_principal_id
  JOIN sys.database_principals memberp ON memberp.principal_id=rm.member_principal_id
  WHERE rolep.name=N'role_app_api' AND memberp.name=N'barrio_app_api'
)
  ALTER ROLE role_app_api ADD MEMBER barrio_app_api;
GO
