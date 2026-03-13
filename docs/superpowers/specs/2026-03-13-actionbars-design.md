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

**Hook direct sur les frames Blizzard** : on récupère les frames existantes par leurs noms globaux et on manipule leur alpha pour le fade.

### Compatibilité addons tiers

Avant de manipuler une barre, vérifier que la frame existe (`if not _G["MainMenuBar"] then return end`). Si ElvUI ou Bartender est détecté (frames absentes ou reparentées), désactiver l'addon pour ces barres et afficher un avertissement.

### Prévention du taint

- **Pas de `UIFrameFadeIn`/`UIFrameFadeOut`** sur les frames Blizzard sécurisées (cause du taint)
- Implémenter un **fade custom** : une frame privée de l'addon avec un `OnUpdate` qui appelle `bar:SetAlpha()` progressivement
- Stocker l'état du fade par barre (alpha courant, alpha cible, durée, elapsed)

### Guard combat (`InCombatLockdown`)

- Toute manipulation de frame doit être précédée d'un check `InCombatLockdown()`
- Si en combat, les opérations sont mises en queue et exécutées au prochain `PLAYER_REGEN_ENABLED`
- Au chargement de l'addon, vérifier l'état de combat avant d'appliquer l'alpha initial

### Mécanisme de Fade et Hover

Pour chaque barre activée :

1. **Init** : `ADDON_LOADED` pour initialiser la DB, `PLAYER_LOGIN` pour créer les overlays et appliquer l'alpha initial (les frames Blizzard sont garanties existantes)
2. **Mouse Enter overlay** : annuler tout FadeOut en cours via `timer:Cancel()`, lancer le fade custom vers alpha 1
3. **Mouse Leave overlay** : démarrer `C_Timer.NewTimer(delay, ...)` (retourne un objet annulable) qui lance le fade custom vers alpha 0
4. **Combat** : si `showInCombat = true`, event `PLAYER_REGEN_DISABLED` → fade vers alpha 1. Event `PLAYER_REGEN_ENABLED` → fade vers alpha 0 (sauf si souris sur la barre)

### Interaction avec Blizzard

- Hooker `bar:HookScript("OnShow", ...)` pour ré-appliquer l'alpha caché quand Blizzard force l'affichage d'une barre
- Ne pas interférer avec l'Edit Mode : désactiver temporairement le fade si l'Edit Mode est actif

### Overlay

- Frame invisible (pas de backdrop) couvrant la même zone que la barre, ancrée via `SetAllPoints(barFrame)`
- `EnableMouse(true)` pour détecter OnEnter/OnLeave
- `SetMouseClickEnabled(false)` pour laisser passer les clics aux boutons d'action (pas de taint, contrairement à `SetPassThroughButtons`)
- Annulation du timer `C_Timer.NewTimer` si la souris revient pendant le délai

### Namespace (`ns`)

Utiliser le pattern `local _, ns = ...` pour partager entre fichiers :

- `ns.db` — référence aux SavedVariables
- `ns.bars` — table des barres gérées (frame, overlay, état du fade, timer)
- `ns.applyBar(barID)` — appliquer/retirer le fade sur une barre
- `ns.resetDefaults()` — remettre tout par défaut
- `ns.settingsCategory` — catégorie du panneau d'options

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
## Title: ZaeUI_ActionBars
## Notes: Hide action bars with mouse hover fade in/out
## Author: loicngr
## Version: 1.0.0
## SavedVariables: ZaeUI_ActionBarsDB

ZaeUI_ActionBars.lua
Options.lua
```
