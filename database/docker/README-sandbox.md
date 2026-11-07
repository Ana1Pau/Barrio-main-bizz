# Ejecutar BARRIO en Docker Sandboxes (app.docker.com)

Stack ya validado localmente (ver abajo). Para correrlo en un Sandbox en la
nube con tus créditos de $250, sigue estos pasos desde **tu propia terminal**
de Windows (requieren tu sesión interactiva: habilitar virtualización,
reiniciar, e iniciar sesión en el navegador — por eso no se pueden ejecutar
de forma remota):

## 1. Habilitar virtualización (PowerShell como Administrador) y reiniciar

```powershell
Enable-WindowsOptionalFeature -Online -FeatureName HypervisorPlatform -All
Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux -All
Enable-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -All
# Reinicia Windows antes de continuar
```

## 2. Instalar el CLI `sbx` e iniciar sesión

```powershell
winget install -h Docker.sbx
sbx login
# Se abre el navegador: inicia sesion con la cuenta donde ya reclamaste los $250
sbx policy set-default balanced
```

## 3. Crear el sandbox con este proyecto montado

Desde la carpeta raíz del repo (`barrio/`):

```powershell
sbx create --name=barrio-db shell .
sbx move barrio-db --to cloud --size small
sbx run barrio-db
```

`--size small` (2 vCPU / 4GB, ~$0.14/hora) es más que suficiente para
desarrollo; con $250 de crédito alcanzan cientos de horas.

## 4. Dentro del sandbox: levantar BarrioDB

Ya dentro de la sesión del sandbox (terminal remota del microVM):

```bash
cd database/docker
cp .env.example .env
# Edita .env y pon una contraseña fuerte para MSSQL_SA_PASSWORD
docker compose up -d sqlserver
docker compose up deploy-schema
```

Al terminar `deploy-schema` deberías ver `Despliegue de BarrioDB
completado.` — exactamente lo que confirmé en la prueba local (39 tablas,
5 procedimientos, datos semilla cargados).

## 5. Pausar para no gastar crédito cuando no lo uses

```bash
docker compose stop
```

Y desde tu máquina: `sbx stop barrio-db` — el cobro por segundo se detiene
mientras el sandbox está detenido.

## Qué ya quedó verificado (hecho por el agente, en local)

- `docker-compose.yml` + `deploy.sh` corridos de extremo a extremo contra un
  motor SQL Server real en contenedor.
- Resultado: 39 tablas, 5 procedimientos almacenados, catálogos semilla
  cargados sin errores.
- Esto es exactamente lo que se ejecutará dentro del Sandbox; solo cambia
  dónde corre el contenedor (tu máquina vs. la microVM en la nube).

## Nota sobre el uso previsto de Docker Sandboxes

Esto es para **desarrollo y pruebas de hoy**, como confirmaste. Para
producción real de BARRIO, la recomendación sigue siendo Azure SQL Database
(ver `database/docs/azure-setup.md`): los Sandboxes se facturan por segundo
y están pensados como entornos efímeros para agentes de código, no como
hosting permanente.
