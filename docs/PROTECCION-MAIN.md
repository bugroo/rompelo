# Protección de `main` (preparada el 07-09-2026, NO activada)

Estado medido el 07-09-2026 con la API de GitHub: `main` tiene `protected: false` y el repo no tiene
rulesets (RMP-016 de la auditoría). Activarlo es una acción remota sobre el repositorio y la decide
José; este documento deja los comandos listos para que la activación sea un paso, no una investigación.

## Qué exige

- El check `rompelo / gate` (workflow `.github/workflows/ci.yml`) en verde antes de integrar.
- Sin push directo a `main`: todo entra por pull request.
- Sin `--force` sobre `main`.

## Comandos (ejecutar José, con `gh` autenticado como `bugroo`)

```bash
gh api -X PUT repos/bugroo/rompelo/branches/main/protection \
  --input - <<'JSON'
{
  "required_status_checks": {"strict": true, "contexts": ["gate"]},
  "enforce_admins": true,
  "required_pull_request_reviews": null,
  "restrictions": null,
  "allow_force_pushes": false,
  "allow_deletions": false
}
JSON
gh api repos/bugroo/rompelo/branches/main/protection --jq '.required_status_checks.contexts'
```

`contexts` tiene que coincidir con el nombre del job (`gate`). Comprobarlo después con un PR de prueba
cuyo gate esté en rojo: si se puede integrar, la protección no está actuando.

## Lo que esto no hace

Hacer obligatorio un juez no lo hace fiable: primero se corrigió el veredicto (bloques A–F de la
auditoría) y solo después tiene sentido exigirlo. Y un `verify --ci` «OK PARCIAL» sigue siendo verde
para GitHub: lo que está sin comprobar (`solo_local`, junta) lo cierra quien lo cruce fuera de CI.
