# Prueba Atalho VPN en tu PC con Docker, sin AWS: servidor + cliente en dos contenedores Ubuntu 24.04.
# Uso (PowerShell, con Docker Desktop abierto):  .\test\probar-local.ps1
$proyecto = (Resolve-Path "$PSScriptRoot\..").Path -replace '\\', '/'

docker info *> $null
if ($LASTEXITCODE -ne 0) { Write-Host "Abre Docker Desktop y vuelve a correr el script." -ForegroundColor Yellow; exit 1 }

function Limpiar { docker rm -f atalho-srv atalho-cli *> $null; docker network rm atalho-test *> $null; docker volume rm atalho-test-out *> $null }
Limpiar
docker network create atalho-test | Out-Null
docker volume create atalho-test-out | Out-Null

$comun = @("--network", "atalho-test", "--privileged", "--sysctl", "net.ipv6.conf.all.disable_ipv6=0",
           "-v", "${proyecto}:/src:ro", "-v", "atalho-test-out:/out", "ubuntu:24.04")
Write-Host "Levantando servidor y cliente (tarda 1-2 min la primera vez)..."
docker run -d --name atalho-srv @comun bash /src/test/servidor.sh | Out-Null
docker run -d --name atalho-cli @comun bash /src/test/cliente.sh | Out-Null

$codSrv = (docker wait atalho-srv); $codCli = (docker wait atalho-cli)
foreach ($c in "atalho-srv", "atalho-cli") {
  docker logs $c 2>&1 | ForEach-Object { "$_" } | Where-Object { $_ -notmatch '^\[#\]|debconf|^\s*$' }
}
Limpiar

if ($codSrv -eq "0" -and $codCli -eq "0") { Write-Host "`nTODO OK" -ForegroundColor Green; exit 0 }
Write-Host "`nHubo fallas (servidor: $codSrv, cliente: $codCli)" -ForegroundColor Red; exit 1
