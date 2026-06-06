#Requires -Version 5.1
param()

#=============================================================
# BOBMUD - Character Creation Script
# Interactive character builder using D&D 2024 rules
#=============================================================

$ErrorActionPreference = "Stop"
$script:ProjectRoot = Split-Path -Parent (Split-Path -Parent $PSCommandPath)

#=============================================================
# LOAD DATA FILES
#=============================================================
function Load-DataFiles {
    $data = @{}
    $files = @{
        classes     = "classes.json"
        species     = "species.json"
        backgrounds = "backgrounds.json"
        feats       = "feats.json"
        equipment   = "equipment.json"
        languages   = "languages.json"
        abilityMods = "ability_modifiers.json"
        alignments  = "alignments.json"
    }

    foreach ($key in $files.Keys) {
        $path = Join-Path $script:ProjectRoot "data\$($files[$key])"
        if (-not (Test-Path $path)) { throw "Missing data file: $path" }
        $data[$key] = Get-Content $path -Raw -Encoding UTF8 | ConvertFrom-Json
    }

    # Convert ability_modifiers to hashtable for fast lookup
    $modTable = @{}
    $data.abilityMods.PSObject.Properties | ForEach-Object { $modTable[$_.Name] = $_.Value }
    $data.abilityMods = $modTable

    return $data
}

#=============================================================
# UI HELPERS
#=============================================================
function Show-Banner {
    Clear-Host
    $c = "Cyan"
    Write-Host "============================================" -ForegroundColor $c
    Write-Host "         BOBMUD - Crear Personaje" -ForegroundColor $c
    Write-Host "        Sistema D&D 2024 (5.5e)" -ForegroundColor $c
    Write-Host "============================================" -ForegroundColor $c
    Write-Host ""
}

function Show-Step {
    param([int]$Number, [string]$Title)
    Write-Host "--- Paso $($Number): $($Title) ---" -ForegroundColor Yellow
    Write-Host ""
}

function Show-Info {
    param([string]$Message)
    Write-Host "  $Message" -ForegroundColor DarkGray
}

function Show-Success {
    param([string]$Message)
    Write-Host "  [OK] $Message" -ForegroundColor Green
}

function Show-Result {
    param([string]$Label, [string]$Value)
    Write-Host ("  {0,-20} {1}" -f "$($Label):", $Value)
}

function Show-Error {
    param([string]$Message)
    Write-Host "  [ERROR] $Message" -ForegroundColor Red
}

function Wait-Key {
    Write-Host ""
    Write-Host "  Presiona ENTER para continuar..." -ForegroundColor DarkGray
    $null = Read-Host
}

#=============================================================
# MENU SELECTION
#=============================================================
function Get-UserChoice {
    param(
        [string]$Prompt,
        [array]$Options,
        [string]$Property = "name",
        [int]$MaxChoices = 1
    )

    $selected = @()

    while ($selected.Count -lt $MaxChoices) {
        Write-Host "`n  $Prompt" -ForegroundColor White
        Write-Host ""

        for ($i = 0; $i -lt $Options.Count; $i++) {
            $label = $Options[$i].$Property
            if (-not $label -and $Options[$i] -is [string]) { $label = $Options[$i] }
            $mark = if ($selected -contains $i) { "[X]" } else { "[ ]" }
            Write-Host "  $mark $($i+1). $label"
        }

        if ($MaxChoices -gt 1 -and $selected.Count -gt 0) {
            $listado = ($selected | ForEach-Object { $Options[$_].$Property }) -join ", "
            Write-Host ""
            Write-Host "  Seleccionados: $listado" -ForegroundColor Green
            Write-Host "  [L] Listo / [C] Cancelar seleccion"
        }

        Write-Host ""
        $input = Read-Host "  > Elige"

        if ($MaxChoices -eq 1) {
            $num = 0
            if ([int]::TryParse($input, [ref]$num) -and $num -ge 1 -and $num -le $Options.Count) {
                return $Options[$num - 1]
            }
            Write-Host "  Opcion invalida (1-$($Options.Count))" -ForegroundColor Red
        }
        else {
            if ($input -eq 'l' -or $input -eq 'L') {
                if ($selected.Count -eq $MaxChoices) { break }
                else { Write-Host "  Debes elegir $MaxChoices opciones" -ForegroundColor Red; continue }
            }
            if ($input -eq 'c' -or $input -eq 'C') { $selected = @(); continue }

            $num = 0
            if ([int]::TryParse($input, [ref]$num) -and $num -ge 1 -and $num -le $Options.Count) {
                $idx = $num - 1
                if ($selected -contains $idx) { $selected = @($selected | Where-Object { $_ -ne $idx }) }
                else { $selected += $idx }
            }
            else { Write-Host "  Opcion invalida" -ForegroundColor Red }
        }
    }

    return @($selected | ForEach-Object { $Options[$_] })
}

#=============================================================
# TEXT INPUT
#=============================================================
function Get-UserText {
    param([string]$Prompt, [string]$Default = "")

    $defaultText = if ($Default) { " [$Default]" } else { "" }
    $input = Read-Host "  > $Prompt$defaultText"
    if ([string]::IsNullOrWhiteSpace($input)) { $input = $Default }
    return $input
}

#=============================================================
# DICE ROLLING
#=============================================================
function Roll-Die {
    param([int]$Sides = 6)
    return (Get-Random -Minimum 1 -Maximum ($Sides + 1))
}

function Roll-4d6-Reroll1 {
    # Roll 4d6, reroll any 1 once, drop lowest, sum the rest
    $dice = @()
    for ($i = 0; $i -lt 4; $i++) {
        $roll = Roll-Die -Sides 6
        if ($roll -eq 1) {
            Show-Info "  Dado $($i+1) saco 1, relanzando..."
            $roll = Roll-Die -Sides 6
            Show-Info "  Relanzado: $roll"
        }
        $dice += $roll
    }

    $sorted = $dice | Sort-Object
    $dropped = $sorted[0]
    $total = ($sorted[1], $sorted[2], $sorted[3] | Measure-Object -Sum).Sum

    return @{
        dice    = $dice
        dropped = $dropped
        total   = $total
    }
}

function Show-RollDetail {
    param($Result)
    $diceStr = ($Result.dice | ForEach-Object { $_.ToString() }) -join ", "
    Write-Host ("    Dados: [{0}]  drop {1}  =>  TOTAL: {2}" -f $diceStr, $Result.dropped, $Result.total) -ForegroundColor Gray
}

#=============================================================
# ABILITY MODIFIER LOOKUP
#=============================================================
function Get-AbilityModifier {
    param([int]$Score)
    $data = $script:loadedData
    $key = [string]$Score
    if ($data.abilityMods.ContainsKey($key)) { return $data.abilityMods[$key] }
    if ($Score -le 1) { return -5 }
    if ($Score -ge 30) { return 10 }
    return [Math]::Floor(($Score - 10) / 2)
}

#=============================================================
# SKILL -> ABILITY MAPPING
#=============================================================
$script:SkillAbilityMap = @{
    acrobatics       = "dexterity"
    animal_handling  = "wisdom"
    arcana           = "intelligence"
    athletics        = "strength"
    deception        = "charisma"
    history          = "intelligence"
    insight          = "wisdom"
    intimidation     = "charisma"
    investigation    = "intelligence"
    medicine         = "wisdom"
    nature           = "intelligence"
    navigation       = "wisdom"
    perception       = "wisdom"
    performance      = "charisma"
    persuasion       = "charisma"
    religion         = "intelligence"
    sleight_of_hand  = "dexterity"
    stealth          = "dexterity"
    survival         = "wisdom"
}

#=============================================================
# CALCULATE CHARACTER
#=============================================================
function Calculate-Character {
    param(
        $Character,
        $Data
    )

    $class = $Data.classes | Where-Object id -eq $Character.class
    $bg    = $Data.backgrounds | Where-Object id -eq $Character.background
    $sp    = $Data.species | Where-Object id -eq $Character.species

    #--- Proficiency Bonus ---
    $Character.proficiency_bonus = 2

    #--- Speed ---
    $Character.speed = $sp.speed

    #--- Hit Points ---
    $conMod = Get-AbilityModifier -Score $Character.abilities.constitution
    switch ($class.hit_die) {
        "d12" { $hpBase = 12 }
        "d10" { $hpBase = 10 }
        "d8"  { $hpBase = 8 }
        "d6"  { $hpBase = 6 }
        default { $hpBase = 8 }
    }
    $hpMax = $hpBase + $conMod
    if ($hpMax -lt 1) { $hpMax = 1 }
    $Character.hit_points = @{
        max       = $hpMax
        current   = $hpMax
        temporary = 0
    }
    $Character.hit_die = $class.hit_die

    #--- Hit Dice ---
    $Character.hit_dice = @{ die = $class.hit_die; total = 1; used = 0 }

    #--- Initiative ---
    $dexMod = Get-AbilityModifier -Score $Character.abilities.dexterity
    $Character.initiative = $dexMod

    #--- Armor Class (base) ---
    $Character.armor_class = 10 + $dexMod

    #--- Saving Throws ---
    $savingThrows = @{}
    foreach ($ab in @("strength","dexterity","constitution","intelligence","wisdom","charisma")) {
        $mod = Get-AbilityModifier -Score $Character.abilities.$ab
        $proficient = $class.saving_throws -contains $ab
        $bonus = if ($proficient) { $Character.proficiency_bonus } else { 0 }
        $total = $mod + $bonus
        $savingThrows[$ab] = @{ modifier = $mod; proficient = $proficient; total = $total }
    }
    $Character.saving_throws = $savingThrows
    $Character.saving_throw_proficiencies = @($class.saving_throws)

    #--- Skill Modifiers ---
    $skillMods = @{}
    foreach ($skill in $script:SkillAbilityMap.Keys) {
        $ab = $script:SkillAbilityMap[$skill]
        $mod = Get-AbilityModifier -Score $Character.abilities.$ab
        $proficient = $Character.skill_proficiencies -contains $skill
        $bonus = if ($proficient) { $Character.proficiency_bonus } else { 0 }
        $total = $mod + $bonus
        $skillMods[$skill] = @{ modifier = $mod; proficient = $proficient; total = $total }
    }
    $Character.skills = $skillMods

    #--- Passive Perception ---
    $percMod = if ($skillMods.ContainsKey("perception")) { $skillMods["perception"].total } else { 0 }
    $Character.passive_perception = 10 + $percMod

    #--- Armor & Weapon Proficiencies ---
    $Character.armor_proficiencies = @($class.armor_proficiencies)
    $Character.weapon_proficiencies = @($class.weapon_proficiencies)

    #--- Traits (from species) ---
    $Character.traits = @($sp.traits)

    #--- Size ---
    $Character.size = $sp.size

    #--- Ability Modifiers ---
    $abMods = @{}
    foreach ($ab in @("strength","dexterity","constitution","intelligence","wisdom","charisma")) {
        $abMods[$ab] = Get-AbilityModifier -Score $Character.abilities.$ab
    }
    $Character.ability_modifiers = $abMods

    #--- Attack Bonus ---
    $strMod = Get-AbilityModifier -Score $Character.abilities.strength
    $Character.melee_attack_bonus = $strMod + $Character.proficiency_bonus
    $Character.ranged_attack_bonus = $dexMod + $Character.proficiency_bonus

    return $Character
}

#=============================================================
# STEP 1: NAME & PLAYER
#=============================================================
function Step-Identity {
    Show-Step -Number 1 -Title "Identidad del Personaje"

    $name = Get-UserText -Prompt "Nombre del personaje"
    $player = Get-UserText -Prompt "Nombre del jugador" -Default $env:USERNAME

    Show-Success "Personaje: $name (Jugador: $player)"
    return @{ name = $name; player = $player }
}

#=============================================================
# STEP 2: CLASS
#=============================================================
function Step-Class {
    param($Data)

    Show-Step -Number 2 -Title "Elegir Clase"

    # Show class overview
    Write-Host "  Clases disponibles:" -ForegroundColor White
    Write-Host ""
    foreach ($cls in $Data.classes) {
        $hpInfo = switch ($cls.hit_die) {
            "d12" { "12 + CON" }; "d10" { "10 + CON" }; "d8" { "8 + CON" }; "d6" { "6 + CON" }
        }
        Write-Host ("  [{0,-12}] HP: {1,-8} Atributo: {2,-12} Salvaciones: {3}" -f $cls.name, $hpInfo, $cls.primary_ability, ($cls.saving_throws -join ", "))
    }

    $chosen = Get-UserChoice -Prompt "Elige tu clase:" -Options $Data.classes -Property "name"
    Write-Host ""

    # Skill selection
    $skillList = $chosen.skills
    $numChoices = [int]$chosen.skill_choices

    if ($numChoices -gt 0 -and $skillList.Count -gt 0) {
        $skillOptions = $skillList | ForEach-Object { @{ name = $_ } }
        Show-Info "Elige $numChoices habilidad(es) de clase:"
        $chosenSkills = Get-UserChoice -Prompt "Skills disponibles:" -Options $skillOptions -Property "name" -MaxChoices $numChoices
        $selectedSkills = $chosenSkills | ForEach-Object { $_.name }
    }
    else {
        $selectedSkills = @()
    }

    Show-Success "Clase: $($chosen.name)"
    if ($selectedSkills.Count -gt 0) {
        Show-Result -Label "Skills" ($selectedSkills -join ", ")
    }

    return @{
        class = $chosen.id
        skill_proficiencies = $selectedSkills
    }
}

#=============================================================
# STEP 3: BACKGROUND
#=============================================================
function Step-Background {
    param($Data)

    Show-Step -Number 3 -Title "Elegir Background"

    Write-Host "  Backgrounds disponibles:" -ForegroundColor White
    Write-Host ""
    foreach ($bg in $Data.backgrounds) {
        $bonusStr = ($bg.ability_bonuses | ForEach-Object { "$($_.ability)+$($_.bonus)" }) -join ", "
        $featName = ($Data.feats | Where-Object id -eq $bg.feat).name
        Write-Host ("  [{0,-14}] Bonus: {1,-18} Dote: {2}" -f $bg.name, $bonusStr, $featName)
    }

    $chosen = Get-UserChoice -Prompt "Elige tu background:" -Options $Data.backgrounds -Property "name"

    $featData = $Data.feats | Where-Object id -eq $chosen.feat
    $featName = if ($featData) { $featData.name } else { $chosen.feat }

    Show-Success "Background: $($chosen.name)"
    Show-Result -Label "Dote" $featName

    return @{
        background = $chosen.id
        feat = $chosen.feat
        tool_proficiencies = @($chosen.tool_proficiencies)
        bg_equipment = @($chosen.equipment)
        bg_ability_bonuses = @($chosen.ability_bonuses)
        bg_languages = [int]$chosen.languages
        bg_skills = @($chosen.skill_proficiencies)
    }
}

#=============================================================
# STEP 4: SPECIES
#=============================================================
function Step-Species {
    param($Data)

    Show-Step -Number 4 -Title "Elegir Especie"

    Write-Host "  Especies disponibles:" -ForegroundColor White
    Write-Host ""
    foreach ($sp in $Data.species) {
        $bonusStr = ""
        $sp.ability_bonuses.PSObject.Properties | ForEach-Object {
            $bonusStr += "$($_.Name)+$($_.Value) "
        }
        Write-Host ("  [{0,-12}] Vel: {1}  Tam: {2,-6}  Bonus: {3}" -f $sp.name, $sp.speed, $sp.size, $bonusStr)
    }

    $chosen = Get-UserChoice -Prompt "Elige tu especie:" -Options $Data.species -Property "name"

    # Get languages from species
    $speciesLangs = @()
    $speciesLangs += $chosen.languages

    Show-Success "Especie: $($chosen.name)"
    Show-Result -Label "Idiomas" ($speciesLangs -join ", ")

    return @{
        species = $chosen.id
        species_languages = $speciesLangs
        species_ability_bonuses = $chosen.ability_bonuses
        species_traits = @($chosen.traits)
    }
}

#=============================================================
# STEP 5: ABILITY SCORES
#=============================================================
function Step-Abilities {
    param($Data, $BgBonus)

    Show-Step -Number 5 -Title "Puntuaciones de Habilidad"

    $allScores = @()
    $attemptsLeft = 3

    while ($attemptsLeft -gt 0) {
        Write-Host "  Generando stats con 4d6 (reroll 1s, descarta el menor)..." -ForegroundColor Cyan
        Write-Host "  Intentos restantes: $attemptsLeft" -ForegroundColor DarkGray
        Write-Host ""

        $allScores = @()
        for ($i = 1; $i -le 6; $i++) {
            $abName = @("","FUE","DES","CON","INT","SAB","CAR")[$i]
            Write-Host "  Stat $i ($abName):" -NoNewline
            $result = Roll-4d6-Reroll1
            Show-RollDetail -Result $result
            $allScores += $result.total
        }

        $sorted = $allScores | Sort-Object -Descending
        Write-Host ""
        Write-Host ("  Puntuaciones: {0}" -f ($sorted -join ",  ")) -ForegroundColor Cyan
        Write-Host ("  Total: {0}" -f ($sorted | Measure-Object -Sum).Sum) -ForegroundColor DarkGray

        Write-Host ""
        $confirm = Read-Host "  > Te gustan estos numeros? (s/n)"
        if ($confirm -eq 's' -or $confirm -eq 'S' -or $confirm -eq 'si' -or $confirm -eq '') {
            break
        }

        $attemptsLeft--
        if ($attemptsLeft -gt 0) {
            Write-Host "  Generando de nuevo..." -ForegroundColor Yellow
        }
    }

    if ($attemptsLeft -eq 0 -and $allScores.Count -eq 0) {
        throw "No se pudieron generar stats"
    }

    # --- Assign scores to abilities ---
    Write-Host ""
    Write-Host "  Asigna tus puntuaciones a los atributos:" -ForegroundColor White
    Write-Host "  Puntuaciones disponibles: $($allScores -join ', ')" -ForegroundColor Cyan
    Write-Host ""

    $abilities = @{ "strength" = 0; "dexterity" = 0; "constitution" = 0; "intelligence" = 0; "wisdom" = 0; "charisma" = 0 }
    $remaining = @($allScores)
    $abOrder = @("strength","dexterity","constitution","intelligence","wisdom","charisma")

    foreach ($ab in $abOrder) {
        while ($true) {
            Write-Host "  Asignar para $ab" -ForegroundColor White
            Write-Host "  Restantes: $($remaining -join ', ')" -ForegroundColor DarkGray
            $choice = Read-Host "  > Elige un numero"

            $num = 0
            if ([int]::TryParse($choice, [ref]$num) -and $remaining -contains $num) {
                $abilities[$ab] = $num
                $removed = $false
                $newRemaining = @()
                foreach ($val in $remaining) {
                    if (-not $removed -and $val -eq $num) {
                        $removed = $true
                    }
                    else {
                        $newRemaining += $val
                    }
                }
                $remaining = $newRemaining
                $mod = Get-AbilityModifier -Score $num
                Show-Result -Label "$ab" "$num (modificador: $mod)"
                break
            }
            else {
                Write-Host "  Numero invalido. Elige de la lista: $($remaining -join ', ')" -ForegroundColor Red
            }
        }
    }

    # --- Apply background bonus ---
    Write-Host ""
    Write-Host "  Aplicando bonus del background..." -ForegroundColor Cyan
    $bonusAbilities = @($BgBonus | ForEach-Object { $_.ability })
    $bonusValues = @($BgBonus | ForEach-Object { [int]$_.bonus })

    # Check if it's +2/+1 or +1/+1/+1
    if ($bonusAbilities.Count -eq 3) {
        # +1/+1/+1: apply all
        foreach ($ab in $bonusAbilities) {
            $idx = [array]::IndexOf($bonusAbilities, $ab)
            $oldScore = $abilities[$ab]
            $newScore = [Math]::Min($oldScore + $bonusValues[$idx], 20)
            $abilities[$ab] = $newScore
            Show-Info "$($ab): $oldScore -> $newScore (+$($bonusValues[$idx]))"
        }
    }
    elseif ($bonusAbilities.Count -ge 2) {
        # +2/+1: user chooses which gets +2 and which gets +1
        Show-Info "Tienes un +2 y un +1 para repartir entre: $($bonusAbilities -join ', ')"
        $primary = Get-UserChoice -Prompt "Que atributo recibe +2?" -Options @($bonusAbilities | ForEach-Object { @{name=$_} }) -Property "name"
        $secondaryList = @($bonusAbilities | Where-Object { $_ -ne $primary.name } | ForEach-Object { @{name=$_} })
        $secondary = Get-UserChoice -Prompt "Que atributo recibe +1?" -Options $secondaryList -Property "name"

        $oldScore = $abilities[$primary.name]
        $newScore = [Math]::Min($oldScore + 2, 20)
        $abilities[$primary.name] = $newScore
        Show-Info "$($primary.name): $oldScore -> $newScore (+2)"

        $oldScore = $abilities[$secondary.name]
        $newScore = [Math]::Min($oldScore + 1, 20)
        $abilities[$secondary.name] = $newScore
        Show-Info "$($secondary.name): $oldScore -> $newScore (+1)"
    }

    # --- Show final stats ---
    Write-Host ""
    Write-Host "  Puntuaciones finales:" -ForegroundColor Green
    Write-Host "  ---------------------" -ForegroundColor DarkGray
    foreach ($ab in @("strength","dexterity","constitution","intelligence","wisdom","charisma")) {
        $mod = Get-AbilityModifier -Score $abilities[$ab]
        $modStr = if ($mod -ge 0) { "+$mod" } else { "$mod" }
        Write-Host ("  {0,-15} {1,2}  (modificador {2})" -f $ab, $abilities[$ab], $modStr) -ForegroundColor White
    }

    return $abilities
}

#=============================================================
# STEP 6: ALIGNMENT
#=============================================================
function Step-Alignment {
    param($Data)

    Show-Step -Number 6 -Title "Alineamiento"

    Write-Host "  Alineamientos:" -ForegroundColor White
    Write-Host ""
    foreach ($al in $Data.alignments) {
        Write-Host ("  [{0,-2}] {1,-18} {2}" -f $al.code, $al.name, $al.description) -ForegroundColor Gray
    }

    $chosen = Get-UserChoice -Prompt "Elige tu alineamiento:" -Options $Data.alignments -Property "name"
    Show-Success "Alineamiento: $($chosen.name) ($($chosen.code))"

    return $chosen.id
}

#=============================================================
# STEP 7: LANGUAGES
#=============================================================
function Step-Languages {
    param($Data, $SpeciesLangs, $ExtraCount)

    Show-Step -Number 7 -Title "Idiomas"

    $languages = @("common")
    $languages += $SpeciesLangs | Where-Object { $_ -ne "common" }

    Write-Host "  Tus idiomas base:" -ForegroundColor Cyan
    Write-Host "  $($languages -join ', ')" -ForegroundColor White
    Write-Host ""

    if ($ExtraCount -gt 0) {
        # Filter out languages already known
        $availableLangs = @($Data.languages.standard | Where-Object { $languages -notcontains $_.id })

        if ($availableLangs.Count -eq 0) {
            Show-Info "Ya conoces todos los idiomas estandar disponibles."
        }
        else {
            if ($availableLangs.Count -lt $ExtraCount) {
                Show-Info "Solo hay $($availableLangs.Count) idioma(s) disponible(s) (ya conoces los demas)."
            }

            Write-Host "  Puedes elegir idioma(s) extra de la lista estandar:" -ForegroundColor White
            Write-Host ""

            for ($i = 0; $i -lt $availableLangs.Count; $i++) {
                $lang = $availableLangs[$i]
                Write-Host ("  [$($i+1)] {0,-20} ({1})" -f $lang.name, $lang.origin)
            }

            $actualCount = [Math]::Min($ExtraCount, $availableLangs.Count)

            for ($e = 0; $e -lt $actualCount; $e++) {
                $chosen = Get-UserChoice -Prompt "Idioma extra $($e+1):" -Options $availableLangs -Property "name"
                $languages += $chosen.id
                Show-Success "Anadido: $($chosen.name)"
                # Remove chosen language from available list for next iteration
                $availableLangs = @($availableLangs | Where-Object { $_.id -ne $chosen.id })
            }
        }
    }

    Show-Success "Idiomas finales: $($languages -join ', ')"
    return $languages
}

#=============================================================
# STEP 8: EQUIPMENT
#=============================================================
function Step-Equipment {
    param($Data, $BgEquipment, $ClassId)

    Show-Step -Number 8 -Title "Equipo Inicial"

    $inventory = @()

    # Auto-assign background equipment
    Write-Host "  Equipo del background:" -ForegroundColor Cyan
    foreach ($item in $BgEquipment) {
        $inventory += @{ id = $item; qty = 1 }
        Write-Host "  * $item"
    }

    Write-Host ""
    Write-Host "  Quieres comprar equipo adicional con tu dinero inicial?" -ForegroundColor White
    $buyMore = Read-Host "  > Comprar? (s/n)"
    if ($buyMore -eq 's' -or $buyMore -eq 'S') {
        Show-Info "Por ahora el equipo se asignara automaticamente. (Funcionalidad avanzada proximamente)"
    }

    return $inventory
}

#=============================================================
# STEP 9: DESCRIPTION
#=============================================================
function Step-Description {
    Show-Step -Number 9 -Title "Descripcion (opcional)"

    $desc = Get-UserText -Prompt "Breve descripcion de tu personaje (opcional)"
    return $desc
}

#=============================================================
# STEP 10: REVIEW & SAVE
#=============================================================
function Step-Review {
    param($Character)

    Show-Step -Number 10 -Title "Resumen del Personaje"

    Write-Host ""
    Write-Host "  =========================================" -ForegroundColor Cyan
    Write-Host "   FICHA DE PERSONAJE" -ForegroundColor Cyan
    Write-Host "  =========================================" -ForegroundColor Cyan
    Write-Host ""

    Show-Result "Nombre" $Character.name
    Show-Result "Jugador" $Character.player
    Show-Result "Clase" $Character.class
    Show-Result "Especie" $Character.species
    Show-Result "Background" $Character.background
    Show-Result "Alineamiento" $Character.alignment
    Show-Result "Nivel" $Character.level
    Show-Result "Experiencia" $Character.experience

    Write-Host ""
    Write-Host "  --- Atributos ---" -ForegroundColor DarkGray
    foreach ($ab in @("strength","dexterity","constitution","intelligence","wisdom","charisma")) {
        $mod = $Character.ability_modifiers[$ab]
        $modStr = if ($mod -ge 0) { "+$mod" } else { "$mod" }
        Write-Host ("  {0,-12} {1,2} ({2})" -f $ab, $Character.abilities[$ab], $modStr)
    }

    Write-Host ""
    Write-Host "  --- Combate ---" -ForegroundColor DarkGray
    Show-Result "HP Maximo" $Character.hit_points.max
    Show-Result "CA" $Character.armor_class
    Show-Result "Iniciativa" $Character.initiative
    Show-Result "Velocidad" "$($Character.speed) ft"
    Show-Result "Bonus de Competencia" "+$($Character.proficiency_bonus)"

    Write-Host ""
    Write-Host "  --- Competencias ---" -ForegroundColor DarkGray
    if ($Character.skill_proficiencies.Count -gt 0) {
        Show-Result "Skills" ($Character.skill_proficiencies -join ", ")
    }
    if ($Character.tool_proficiencies.Count -gt 0) {
        Show-Result "Tools" ($Character.tool_proficiencies -join ", ")
    }
    Show-Result "Salvaciones" ($Character.saving_throw_proficiencies -join ", ")

    Write-Host ""
    Write-Host "  --- Idiomas ---" -ForegroundColor DarkGray
    Show-Result "Idiomas" ($Character.languages -join ", ")

    Write-Host ""
    Write-Host "  --- Dotes y Rasgos ---" -ForegroundColor DarkGray
    if ($Character.feats.Count -gt 0) {
        Show-Result "Dotes" ($Character.feats -join ", ")
    }
    if ($Character.traits.Count -gt 0) {
        Show-Result "Rasgos" ($Character.traits -join ", ")
    }

    Write-Host ""

    # Confirm save
    $confirm = Read-Host "  > Guardar personaje? (s/n)"
    if ($confirm -eq 's' -or $confirm -eq 'S' -or $confirm -eq 'si') {
        return $true
    }
    return $false
}

#=============================================================
# SAVE CHARACTER
#=============================================================
function Save-Character {
    param($Character)

    $playersPath = Join-Path $script:ProjectRoot "data\players.json"

    # Load existing
    $playersData = Get-Content $playersPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if (-not $playersData) {
        $playersData = @{ version = 1; players = @() }
    }

    # Generate ID
    $newId = [guid]::NewGuid().ToString()

    # Ensure all properties exist on the object (it may be a minimal test object)
    $meta = @{
        id         = $newId
        created_at = (Get-Date -Format "o")
        updated_at = (Get-Date -Format "o")
        level      = 1
        experience = 0
    }
    foreach ($prop in $meta.Keys) {
        if ($Character.PSObject.Properties.Name -contains $prop) {
            $Character.$prop = $meta[$prop]
        }
        else {
            $Character | Add-Member -NotePropertyName $prop -NotePropertyValue $meta[$prop]
        }
    }

    $playersList = @($playersData.players) + $Character
    $playersData.players = $playersList

    $playersData | ConvertTo-Json -Depth 10 | Set-Content $playersPath -Encoding UTF8

    return $newId
}

#=============================================================
# ADMIN MENU
#=============================================================
function Show-AdminMenu {
    Show-Banner
    Write-Host "  =========================================" -ForegroundColor Red
    Write-Host "          MENU DE ADMINISTRACION" -ForegroundColor Red
    Write-Host "  =========================================" -ForegroundColor Red
    Write-Host ""

    while ($true) {
        Write-Host "  Opciones:" -ForegroundColor White
        Write-Host ""
        Write-Host "  [1] Listar todos los personajes"
        Write-Host "  [2] Salir"
        Write-Host ""
        $option = Read-Host "  > Elige"

        switch ($option) {
            "1" {
                Write-Host ""
                $playersPath = Join-Path $script:ProjectRoot "data\players.json"
                if (-not (Test-Path $playersPath)) {
                    Write-Host "  No hay archivo de personajes aun." -ForegroundColor Yellow
                }
                else {
                    $playersData = Get-Content $playersPath -Raw -Encoding UTF8 | ConvertFrom-Json
                    $players = $playersData.players
                    if ($players.Count -eq 0) {
                        Write-Host "  No hay personajes registrados." -ForegroundColor Yellow
                    }
                    else {
                        Write-Host ("  {0,-5} {1,-15} {2,-12} {3,-12} {4,-14} {5,-6} {6}" -f "ID", "Nombre", "Clase", "Especie", "Background", "Nivel", "Jugador") -ForegroundColor Cyan
                        Write-Host ("  {0,-5} {1,-15} {2,-12} {3,-12} {4,-14} {5,-6} {6}" -f ("-"*5), ("-"*15), ("-"*12), ("-"*12), ("-"*14), ("-"*6), ("-"*15)) -ForegroundColor DarkGray
                        $i = 1
                        foreach ($p in $players) {
                            $idShort = $p.id.Substring(0, [Math]::Min($p.id.Length, 5))
                            Write-Host ("  {0,-5} {1,-15} {2,-12} {3,-12} {4,-14} {5,-6} {6}" -f $idShort, $p.name, $p.class, $p.species, $p.background, $p.level, $p.player)
                            $i++
                        }
                    }
                }
                Write-Host ""
                Write-Host "  Presiona ENTER para volver al menu..." -ForegroundColor DarkGray
                $null = Read-Host
                Show-Banner
                Write-Host "  =========================================" -ForegroundColor Red
                Write-Host "          MENU DE ADMINISTRACION" -ForegroundColor Red
                Write-Host "  =========================================" -ForegroundColor Red
                Write-Host ""
            }
            "2" {
                Write-Host ""
                Write-Host "  Saliendo del programa..." -ForegroundColor Yellow
                Write-Host "  Presiona ENTER para salir..." -ForegroundColor DarkGray
                $null = Read-Host
                exit
            }
            default {
                Write-Host "  Opcion invalida." -ForegroundColor Red
            }
        }
    }
}

#=============================================================
# MAIN
#=============================================================
function Main {
    Show-Banner

    # Load data
    Write-Host "  Cargando datos de juego..." -ForegroundColor DarkGray
    $script:loadedData = Load-DataFiles
    Show-Success "Datos cargados correctamente"
    Start-Sleep -Milliseconds 300

    #--- STEP 1: Identity ---
    Show-Banner
    $identity = Step-Identity

    # Check for admin mode (name OR player)
    if ($identity.name -eq "admin" -or $identity.player -eq "admin") {
        Show-AdminMenu
        return
    }

    Wait-Key

    #--- STEP 2: Class ---
    Show-Banner
    $classResult = Step-Class -Data $script:loadedData
    Wait-Key

    #--- STEP 3: Background ---
    Show-Banner
    $bgResult = Step-Background -Data $script:loadedData
    Wait-Key

    #--- STEP 4: Species ---
    Show-Banner
    $speciesResult = Step-Species -Data $script:loadedData
    Wait-Key

    #--- STEP 5: Abilities ---
    Show-Banner
    $abilities = Step-Abilities -Data $script:loadedData -BgBonus $bgResult.bg_ability_bonuses
    Wait-Key

    #--- STEP 6: Alignment ---
    Show-Banner
    $alignment = Step-Alignment -Data $script:loadedData
    Wait-Key

    #--- STEP 7: Languages ---
    Show-Banner
    $languages = Step-Languages -Data $script:loadedData -SpeciesLangs $speciesResult.species_languages -ExtraCount $bgResult.bg_languages
    Wait-Key

    #--- STEP 8: Equipment ---
    Show-Banner
    $equipment = Step-Equipment -Data $script:loadedData -BgEquipment $bgResult.bg_equipment -ClassId $classResult.class
    Wait-Key

    #--- STEP 9: Description ---
    Show-Banner
    $description = Step-Description

    #--- BUILD CHARACTER OBJECT ---
    $character = [PSCustomObject]@{
        id                    = ""
        name                  = $identity.name
        player                = $identity.player
        level                 = 1
        experience            = 0
        class                 = $classResult.class
        species               = $speciesResult.species
        background            = $bgResult.background
        alignment             = $alignment
        size                  = ""
        speed                 = 0
        abilities             = $abilities
        hit_die               = ""
        hit_dice              = @{}
        hit_points            = @{}
        armor_class           = 0
        initiative            = 0
        proficiency_bonus     = 0
        ability_modifiers     = @{}
        saving_throws         = @{}
        saving_throw_proficiencies = @()
        skill_proficiencies   = @($classResult.skill_proficiencies) + @($bgResult.bg_skills)
        skills                = @{}
        tool_proficiencies    = $bgResult.tool_proficiencies
        armor_proficiencies   = @()
        weapon_proficiencies  = @()
        languages             = $languages
        feats                 = @($bgResult.feat)
        traits                = @()
        equipment             = $equipment
        currency              = @{ cp = 0; sp = 0; gp = 0; ep = 0; pp = 0 }
        description           = $description
        melee_attack_bonus    = 0
        ranged_attack_bonus   = 0
        passive_perception    = 0
        created_at            = ""
        updated_at            = ""
    }

    #--- CALCULATE DERIVED STATS ---
    $character = Calculate-Character -Character $character -Data $script:loadedData

    #--- REVIEW ---
    Show-Banner
    $saved = Step-Review -Character $character

    if ($saved) {
        $newId = Save-Character -Character $character
        Show-Success "Personaje guardado con ID: $newId!"
        Show-Info "Archivo: data\players.json"
    }
    else {
        Write-Host ""
        Write-Host "  Creacion cancelada. El personaje no fue guardado." -ForegroundColor Yellow
    }

    Write-Host ""
    Write-Host "  Presiona ENTER para salir..." -ForegroundColor DarkGray
    $null = Read-Host
}

#=============================================================
# RUN (only if executed directly, not dot-sourced)
#=============================================================
if ($MyInvocation.InvocationName -ne '.') {
    try {
        Main
    }
    catch {
        Write-Host ""
        Write-Host "  ERROR: $_" -ForegroundColor Red
        Write-Host "  $($_.ScriptStackTrace)" -ForegroundColor DarkGray
        Write-Host ""
        Write-Host "  Presiona ENTER para salir..." -ForegroundColor DarkGray
        $null = Read-Host
    }
}
