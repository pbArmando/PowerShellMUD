# PowerShellMUD

Un MUD (Multi-User Dungeon) basado en D&D 2024 (5.5e), construido completamente en PowerShell.

## Requisitos

- Windows con PowerShell 5.1+
- Git (opcional, para control de versiones)

## Instalacion

```powershell
git clone https://github.com/pbArmando/PowerShellMUD.git
cd PowerShellMUD
```

## Uso

### Crear personaje

```powershell
PowerShell -ExecutionPolicy Bypass -File "scripts\create_character.ps1"
```

Flujo de 9 pasos:
1. **Identidad** — nombre del personaje y jugador
2. **Clase** — 12 clases de D&D 2024 (barbaro, bardo, clerigo, druida, guerrero, monje, paladin, explorador, picaro, hechicero, brujo, mago)
3. **Trasfondo** — 10 trasfondos con bonuses de habilidad y dotes de origen
4. **Especie** — 9 especies (humano, elfo, enano, mediano, gnomo, semiorco, tiflin, dragonborn, aquelarre)
5. **Estadisticas** — 4d6 (reroll 1s, descarta menor), hasta 3 intentos, asignacion manual
6. **Alineamiento** — 9 alineamientos
7. **Idiomas** — seleccion segun especie e inteligencia
8. **Equipo** — armas y armaduras
9. **Descripcion** — apariencia, personalidad e historia

### Explorar el mundo

```powershell
PowerShell -ExecutionPolicy Bypass -File "scripts\play.ps1"
```

Comandos:
- `n`, `s`, `e`, `w` — mover en el grid 2x2
- `l` — mirar la sala actual
- `q` — salir

Cada personaje tiene HP, MP y Puntos de Movimiento (`modificador de destreza * 5`) que se gastan al moverse.

## Datos

Todos los datos del juego estan en `data/` como JSON:
- `classes.json` — 12 clases con dados de golpe, competencias y habilidades
- `species.json` — 9 especies con bonuses raciales
- `backgrounds.json` — 10 trasfondos con bonuses y equipo
- `feats.json` — 38 dotes de origen
- `equipment.json` — armas y armaduras
- `rooms.json` — grid 2x2 del mundo
- `players.json` — personajes guardados

## Pendiente

- [ ] Subclases (nivel 3+)
- [ ] Sistema de conjuros
- [ ] Subida de nivel
- [ ] Combate
- [ ] Items y loot
- [ ] Mundo expansible
