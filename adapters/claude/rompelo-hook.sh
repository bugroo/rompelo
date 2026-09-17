#!/bin/bash
# Adaptador Claude Code · hooks PreToolUse (Bash) y UserPromptSubmit. Contrato oficial (code.claude.com/docs/en/hooks,
# leído 16-09-2026): stdin JSON con hook_event_name; rompelo decide por el evento:
#   PreToolUse       → {"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":…}} o nada
#   UserPromptSubmit → {"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":…}} o nada
#   Stop             → {"decision":"block","reason":…} o nada (rompelo-stop.sh sigue valiendo para Stop)
exec "$HOME/rompelo/bin/rompelo" hook claude
