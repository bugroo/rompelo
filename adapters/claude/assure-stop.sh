#!/bin/bash
# Adaptador Claude Code · hook Stop. Contrato oficial (code.claude.com/docs/en/hooks, leído 04-09-2026):
#   stdin  {session_id, cwd, stop_hook_active, ...}
#   stdout {"decision":"block","reason":"..."} para impedir el cierre; nada para dejar parar.
#   Claude Code corta solo tras 8 bloqueos seguidos; assure se corta antes, a los 3.
exec "$HOME/assure/bin/assure" hook claude
