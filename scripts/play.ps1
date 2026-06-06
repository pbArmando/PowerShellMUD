#=============================================================
# BOBMUD - Jugar
# Sistema D&D 2024 (5.5e)
#=============================================================

$script:ProjectRoot = Split-Path -Parent $PSScriptRoot

# --- Display helpers ---
function Show-Info { param($Message) Write-Host "  $Message" -ForegroundColor DarkGray }
function Show-Success { param($Message) Write-Host ("  [+] " + $Message) -ForegroundColor Green }
function Show-Result { param($Label, $Value) Write-Host ("  {0,-15} {1}" -f ("[$Label]", $Value)) -ForegroundColor White }

# --- Data loaders ---
function Load-CharacterList {
    $path = "$script:ProjectRoot\data\players.json"
    $data = Get-Content $path -Raw -Encoding UTF8 | ConvertFrom-Json
    return $data.players
}

function Load-Rooms {
    $path = "$script:ProjectRoot\data\rooms.json"
    $data = Get-Content $path -Raw -Encoding UTF8 | ConvertFrom-Json
    return $data
}

function Load-AbilityModifiers {
    $path = "$script:ProjectRoot\data\ability_modifiers.json"
    return Get-Content $path -Raw -Encoding UTF8 | ConvertFrom-Json
}

# --- Room helpers ---
function Get-Room {
    param($Rooms, $X, $Y)
    return $Rooms.rooms | Where-Object { $_.x -eq $X -and $_.y -eq $Y }
}

function Get-AvailableExits {
    param($Room)
    $dirs = @()
    if ($Room.exits.n) { $dirs += "N" }
    if ($Room.exits.s) { $dirs += "S" }
    if ($Room.exits.e) { $dirs += "E" }
    if ($Room.exits.w) { $dirs += "W" }
    if ($dirs.Count -eq 0) { return "ninguna" }
    return $dirs -join " "
}

# --- Session helpers ---
function Show-Status {
    param($Session)
    Write-Host ("  HP: {0}/{1}  |  MP: {2}/{3}  |  Mov: {4}/{5}" -f
        $Session.hpCurrent, $Session.hpMax,
        $Session.mpCurrent, $Session.mpMax,
        $Session.moveCurrent, $Session.moveMax) -ForegroundColor DarkGray
}

#=============================================================
# MAIN (solo corre cuando se ejecuta directamente)
#=============================================================
if ($MyInvocation.InvocationName -ne '.') { Clear-Host
Write-Host "============================================" -ForegroundColor Yellow
Write-Host "          BOBMUD - Explorar" -ForegroundColor Yellow
Write-Host "============================================" -ForegroundColor Yellow

# Load world
$roomsData = Load-Rooms
Write-Host "`n  Mundo cargado: $($roomsData.grid_width)x$($roomsData.grid_height) habitaciones" -ForegroundColor DarkGray

# Load and select character
$players = Load-CharacterList
if ($players.Count -eq 0) {
    Write-Host "`n  No hay personajes. Crea uno primero:" -ForegroundColor Red
    Write-Host "  PowerShell -ExecutionPolicy Bypass -File `"$PSScriptRoot\create_character.ps1`"" -ForegroundColor Cyan
    exit
}

Write-Host "`n  Selecciona tu personaje:" -ForegroundColor White
Write-Host ""
for ($i = 0; $i -lt $players.Count; $i++) {
    $p = $players[$i]
    Write-Host ("  [{0}] {1,-15} ({2}, nivel {3})" -f ($i+1), $p.name, $p.class, $p.level) -ForegroundColor Gray
}

while ($true) {
    $sel = Read-Host "`n  > Elige un numero"
    $idx = 0
    if ([int]::TryParse($sel, [ref]$idx) -and $idx -ge 1 -and $idx -le $players.Count) {
        $character = $players[$idx - 1]
        break
    }
    Write-Host "  Numero invalido" -ForegroundColor Red
}

Write-Host ""
Show-Success ("Personaje: {0} ({1})" -f $character.name, $character.class)

# Session state
$abilityMods = Load-AbilityModifiers
$dexMod = [int]($abilityMods.("$($character.abilities.dexterity)"))
$conMod = [int]($abilityMods.("$($character.abilities.constitution)"))
$moveMax = [Math]::Max(1, $dexMod * 5)
$mpMax = [Math]::Max(1, $character.level * 3)

$session = @{
    hpMax = $character.hit_points.max
    hpCurrent = $character.hit_points.max
    mpMax = $mpMax
    mpCurrent = $mpMax
    moveMax = $moveMax
    moveCurrent = $moveMax
}

# Position
$pos = @{ x = 0; y = 0 }

#=============================================================
# GAME LOOP
#=============================================================
while ($true) {
    $room = Get-Room -Rooms $roomsData -X $pos.x -Y $pos.y
    Write-Host ""
    Write-Host ("[ {0} ]" -f $room.name) -ForegroundColor Yellow
    Write-Host ("  Salidas: {0}" -f (Get-AvailableExits $room)) -ForegroundColor DarkGray
    Show-Status -Session $session

    $input = Read-Host "`n  > "
    $input = $input.ToLower().Trim()

    if ($input -eq "" -or $input -eq "l" -or $input -eq "look" -or $input -eq "mirar") {
        continue
    }

    if ($input -eq "q" -or $input -eq "quit" -or $input -eq "exit" -or $input -eq "salir") {
        Write-Host ""
        Write-Host "  Hasta luego!" -ForegroundColor Green
        break
    }

    $dir = ""
    if ($input -in "n","north","norte")     { $dir = "n" }
    elseif ($input -in "s","south","sur")   { $dir = "s" }
    elseif ($input -in "e","east","este")   { $dir = "e" }
    elseif ($input -in "w","west","oeste")  { $dir = "w" }

    if ($dir -eq "") {
        Write-Host "  Usa: n (norte), s (sur), e (este), w (oeste), l (mirar), q (salir)" -ForegroundColor Red
        continue
    }

    if ($session.moveCurrent -le 0) {
        Write-Host "  Estas demasiado cansado para moverte." -ForegroundColor Red
        continue
    }

    $next = $room.exits.$dir
    if ($null -eq $next) {
        Write-Host "  No hay salida." -ForegroundColor Red
    }
    else {
        $pos.x = $next.x
        $pos.y = $next.y
        $session.moveCurrent--
    }
}
}
