#!/bin/bash
# Adaptador Claude Code · hooks PostToolUse y PostToolUseFailure (sin matcher). Observa cada herramienta, nunca bloquea.
# PostToolUse solo llega tras éxito; un comando con salida != 0 llega por PostToolUseFailure (doc oficial, INC-0031).
# Contrato oficial: stdin {session_id, cwd, tool_name, tool_input, tool_response};
# stdout opcional {"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"…"}}.
exec "$HOME/rompelo/bin/rompelo" observe claude
