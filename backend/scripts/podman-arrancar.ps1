# Arranca la máquina de Podman y deja lista la tubería que usa
# `podman compose` (y cualquier cliente de la API de Docker).
#
# Por qué hace falta (Windows + WSL, comprobado el 2026-11-17 con Podman
# 5.8.10 y WSL 3.0.5): `podman machine start` lanza win-sshproxy para crear
# dos tuberías, la suya (podman-machine-default) y `docker_engine`. Con Docker
# Desktop instalado, la de `docker_engine` falla y win-sshproxy termina sin
# crear ninguna; `podman` sigue funcionando por SSH, pero `podman compose`
# (que usa docker-compose.exe por la tubería) no.
#
# Uso:  powershell -ExecutionPolicy Bypass -File backend\scripts\podman-arrancar.ps1
#       luego, en backend\:  podman compose up -d

$ErrorActionPreference = 'Stop'
$machine = 'podman-machine-default'
$pipe = "\\.\pipe\$machine"

$state = podman machine inspect $machine --format '{{.State}}'
if ($state -ne 'running') {
    # Avisa del fallo de la API de Docker; no es un error para nosotros.
    podman machine start $machine 2>&1 | Out-Host
}

if ([IO.Directory]::GetFiles('\\.\pipe\') -contains $pipe) {
    Write-Host "La tubería $pipe ya existe."
    return
}

$uri = podman system connection list --format '{{.Name}} {{.URI}}' |
    Where-Object { $_ -match "^$machine " } |
    ForEach-Object { ($_ -split ' ', 2)[1] }
if (-not $uri) { throw "No hay conexión de Podman para $machine." }
$uri = $uri -replace '127\.0\.0\.1', 'localhost'

$identity = Join-Path $env:USERPROFILE '.local\share\containers\podman\machine\machine'
$stateDir = Join-Path $env:USERPROFILE ".local\share\containers\podman\machine\wsl\$machine"
$proxy = Join-Path $env:ProgramFiles 'RedHat\Podman\win-sshproxy.exe'

# Solo la tubería de Podman: la de docker_engine es la que lo hace fallar.
Start-Process $proxy -WindowStyle Hidden -ArgumentList @(
    $machine, $stateDir, "npipe:////./pipe/$machine", $uri, $identity
)

for ($i = 0; $i -lt 20; $i++) {
    if ([IO.Directory]::GetFiles('\\.\pipe\') -contains $pipe) {
        Write-Host "Podman listo: $pipe"
        return
    }
    Start-Sleep -Milliseconds 500
}
throw "win-sshproxy no creó $pipe."
