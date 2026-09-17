# Protección de `main` (activada el 16-09-2026)

El 16-09-2026 se activó la protección de rama de `bugroo/rompelo`, al retomar los pendientes del
Mac y GitHub por encargo de José. Una lectura nueva de la API confirmó `gate` obligatorio,
rama actualizada, PR obligatorio, aplicación a administradores y bloqueo de force-push y borrado.
Se usa protección de rama clásica; no se creó un ruleset adicional.
La configuración se releyó el 17-09-2026 y conserva esos requisitos.

## Qué exige

- El check `rompelo / gate` (workflow `.github/workflows/ci.yml`) en verde antes de integrar.
- Sin push directo a `main`: todo entra por pull request.
- No exige un segundo revisor: el número de aprobaciones es cero.
- Sin `--force` ni borrado de `main`, también para administradores.

## Configuración aplicada

```bash
gh api -X PUT repos/bugroo/rompelo/branches/main/protection \
  --input - <<'JSON'
{
  "required_status_checks": {"strict": true, "contexts": ["gate"]},
  "enforce_admins": true,
  "required_pull_request_reviews": {
    "dismiss_stale_reviews": false,
    "require_code_owner_reviews": false,
    "required_approving_review_count": 0,
    "require_last_push_approval": false
  },
  "restrictions": null,
  "allow_force_pushes": false,
  "allow_deletions": false
}
JSON
gh api repos/bugroo/rompelo/branches/main/protection --jq '.required_status_checks.contexts'
```

`contexts` coincide con el nombre real del job (`gate`). El ejemplo anterior usaba
`required_pull_request_reviews: null`, que desactiva ese requisito; ahora el objeto exige PR sin
pedir aprobaciones de otro colaborador. Véase la
[API oficial de protección de ramas](https://docs.github.com/en/rest/branches/branch-protection#update-branch-protection).

La relectura de la regla comprueba su configuración. La comprobación operacional consiste en
observar un PR con `gate` fallido y estado de integración `BLOCKED`; no requiere intentar fusionarlo.
Un PR en borrador tampoco demuestra por sí solo que el bloqueo proceda del check.

## Lo que esto no hace

Hacer obligatorio un juez no lo hace fiable: primero se corrigió el veredicto (bloques A–F de la
auditoría) y solo después tiene sentido exigirlo. Y un `verify --ci` «OK PARCIAL» sigue siendo verde
para GitHub: lo que está sin comprobar (`solo_local`, junta) lo cierra quien lo cruce fuera de CI.
