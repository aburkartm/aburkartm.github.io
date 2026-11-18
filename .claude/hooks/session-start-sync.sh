#!/bin/sh
# .claude/hooks/session-start-sync.sh
# SessionStart: 1) git pull, 2) recien despues configurar core.hooksPath.
# El orden importa: si se configura core.hooksPath antes de que el pull traiga
# .githooks/ al disco, git apunta a una carpeta sin el script real y no ejecuta
# nada, en silencio.
# Red acotada (regla hooks-red-acotada-y-lock-huerfano): GIT_TERMINAL_PROMPT=0
# para que no espere credenciales y timeout 30 para que no se cuelgue.
# Todo el cuerpo va en main() y la ultima linea es "main; exit": bash lee un
# script de a trozos, y editarlo mientras corre mata la corrida con un error de
# sintaxis que no existe en el archivo (sesiones-paralelas-repos-compartidos, punto 8).
# Copia del de claude-skills sin el reloadSkills, que solo importa donde hay skills.

main() {
    cd "$CLAUDE_PROJECT_DIR" || exit 0

    PULL_OUTPUT=$(GIT_TERMINAL_PROMPT=0 timeout 30 git pull 2>&1)
    PULL_EXIT=$?

    if [ "$PULL_EXIT" -ne 0 ]; then
        export HOOK_PULL_OUTPUT="$PULL_OUTPUT"
        export HOOK_PROJECT_DIR="$CLAUDE_PROJECT_DIR"
        python -c "
import json, os
proj = os.environ.get('HOOK_PROJECT_DIR', '')
out = os.environ.get('HOOK_PULL_OUTPUT', '')
msg = 'ADVERTENCIA: git pull fallo en ' + proj + '.\nRevisar conflictos o cambios locales sin commitear antes de seguir.\n\n' + out
print(json.dumps({'systemMessage': msg, 'hookSpecificOutput': {'hookEventName': 'SessionStart', 'additionalContext': msg}}))
"
        exit 0
    fi

    LOCAL_HOOKS=$(git config --local --get core.hooksPath 2>/dev/null)
    if [ -z "$LOCAL_HOOKS" ]; then
        git config core.hooksPath .githooks
    elif [ "$LOCAL_HOOKS" != ".githooks" ]; then
        echo "AVISO: core.hooksPath ya esta seteado a '$LOCAL_HOOKS' - no lo sobrescribo" >&2
    fi

    exit 0
}

main "$@"; exit
