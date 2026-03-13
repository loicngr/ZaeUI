# ZaeUI_ActionBars — Design Spec

## Objectif

Addon WoW Retail permettant de cacher les barres d'action par défaut, avec affichage au survol de la souris (FadeIn) et disparition après un délai configurable (FadeOut).

## Barres ciblées

| Barre | Frame Blizzard | ID interne |
|-------|---------------|------------|
| Action Bar 1 | `MainMenuBar` | `bar1` |
| Action Bar 2 | `MultiBarBottomLeft` | `bar2` |
| Action Bar 3 | `MultiBarBottomRight` | `bar3` |
| Action Bar 4 | `MultiBarRight` | `bar4` |
| Action Bar 5 | `MultiBarLeft` | `bar5` |
| Action Bar 6 | `MultiBar5` | `bar6` |
| Action Bar 7 | `MultiBar6` | `bar7` |
| Action Bar 8 | `MultiBar7` | `bar8` |
| Stance Bar | `StanceBar` | `stance` |
| Pet Bar | `PetActionBar` | `pet` |

## Approche technique

**Hook direct sur les frames Blizzard** : on récupère les frames existantes par leurs noms globaux et on applique le fade via `UIFrameFadeIn`/`UIFrameFadeOut`.

### Mécanisme de Fade et Hover

Pour chaque barre activée :

1. **Init** (PLAYER_LOGIN) : mettre la barre à `SetAlpha(0)` et créer une frame overlay invisible ancrée sur la frame Blizzard
2. **Mouse Enter overlay** : annuler tout FadeOut en cours, lancer `UIFrameFadeIn(bar, fadeInDuration, 0, 1)`
3. **Mouse Leave overlay** : démarrer `C_Timer.After(delay, ...)` qui lance `UIFrameFadeOut(bar, fadeOutDuration, 1, 0)`
4. **Combat** : si `showInCombat = true`, event `PLAYER_REGEN_DISABLED` → force `SetAlpha(1)`. Event `PLAYER_REGEN_ENABLED` → remet `SetAlpha(0)` avec fade out

### Overlay

- Frame invisible (pas de backdrop, `SetAlpha(0)`) couvrant la même zone que la barre
- `EnableMouse(true)` pour détecter OnEnter/OnLeave
- `SetPassThroughButtons("LeftButton", "RightButton")` pour laisser passer les clics aux boutons d'action
- Annulation du timer si la souris revient pendant le délai

## SavedVariables

```lua
ZaeUI_ActionBarsDB = {
    bars = {
        bar1 = { enabled = false, fadeIn = 0.3, fadeOut = 0.3, delay = 1.0, showInCombat = true },
        bar2 = { enabled = false, fadeIn = 0.3, fadeOut = 0.3, delay = 1.0, showInCombat = true },
        bar3 = { enabled = false, fadeIn = 0.3, fadeOut = 0.3, delay = 1.0, showInCombat = true },
        bar4 = { enabled = false, fadeIn = 0.3, fadeOut = 0.3, delay = 1.0, showInCombat = true },
        bar5 = { enabled = false, fadeIn = 0.3, fadeOut = 0.3, delay = 1.0, showInCombat = true },
        bar6 = { enabled = false, fadeIn = 0.3, fadeOut = 0.3, delay = 1.0, showInCombat = true },
        bar7 = { enabled = false, fadeIn = 0.3, fadeOut = 0.3, delay = 1.0, showInCombat = true },
        bar8 = { enabled = false, fadeIn = 0.3, fadeOut = 0.3, delay = 1.0, showInCombat = true },
        stance = { enabled = false, fadeIn = 0.3, fadeOut = 0.3, delay = 1.0, showInCombat = true },
        pet = { enabled = false, fadeIn = 0.3, fadeOut = 0.3, delay = 1.0, showInCombat = true },
    }
}
```

Toutes les barres désactivées par défaut (`enabled = false`).

## Slash Command

```
/zab         → ouvre le panneau d'options
/zab help    → affiche l'aide
/zab reset   → remet tout par défaut
```

## Panneau d'options

Pour chaque barre, une section avec :

- **Checkbox** : activer/désactiver le hide
- **Checkbox** : montrer en combat
- **Slider** : Fade In (0.1 – 1.0s, pas de 0.1)
- **Slider** : Fade Out (0.1 – 1.0s, pas de 0.1)
- **Slider** : Délai avant Fade Out (0.0 – 3.0s, pas de 0.1)

## Structure fichiers

```
ZaeUI_ActionBars/
├── ZaeUI_ActionBars.toc
├── ZaeUI_ActionBars.lua    -- Entry point, events, slash command, fade logic
└── Options.lua             -- Panneau d'options
```

## TOC

```
## Interface: 120000
## Title: ZaeUI ActionBars
## Notes: Hide action bars with mouse hover fade in/out
## Author: loicngr
## Version: 1.0.0
## SavedVariables: ZaeUI_ActionBarsDB

ZaeUI_ActionBars.lua
Options.lua
```
