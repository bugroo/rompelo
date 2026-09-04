#!/bin/bash
# Adaptador Claude Code · hook PostToolUse (sin matcher). Observa cada herramienta, nunca bloquea.
# Contrato oficial: stdin {session_id, cwd, tool_name, tool_input, tool_response};
# stdout opcional {"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"…"}}.
exec "$HOME/rompelo/bin/rompelo" observe claude
