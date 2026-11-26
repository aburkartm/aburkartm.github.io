#!/bin/sh
# .claude/hooks/session-start-sync.sh
# ARCHIVO IDENTICO EN LOS 15 REPOS PROPIOS DE C:\Dev que lo registran en
# SessionStart. Al corregir algo aca, copiarlo a los otros 14: el eje 10 de
# salud-sistema (claude-skills/salud-sistema/gemelos.txt) avisa si divergen.
# Test: claude-skills/.claude/hooks/tests/test_session_start_sync.py.
#
# SessionStart: 1) git pull solo de avance rapido, 2) core.hooksPath,
# 3) re-escaneo de skills si el pull trajo algo. Nunca bloquea: sale siempre 0,
# y todo aviso va en un unico JSON (systemMessage + additionalContext), porque
# lo que un hook con salida 0 escribe a stderr no lo ve nadie (hooks.md).
#
# 1) --ff-only: con historias divergentes un pull normal deja un merge a medias
#    (MERGE_HEAD) en el arbol que comparten las sesiones abiertas, y el
#    session-end-sync de cada repo lo cerraria con los marcadores de conflicto
#    adentro. Ahora el pull se niega y el aviso dice como resolverlo a mano.
#    Red acotada (regla hooks-red-acotada-y-lock-huerfano): GIT_TERMINAL_PROMPT=0,
#    timeout 30 y corte por red estancada (lowSpeedLimit/lowSpeedTime).
# 2) Se configura .githooks solo si la carpeta trae su pre-commit, y aunque el
#    pull haya fallado: un clon nuevo sin red igual queda con sus hooks de git.
#    El orden importa: si se configurara antes de que el pull traiga .githooks/
#    al disco, git apuntaria a una carpeta vacia y no ejecutaria nada.
# 3) El descubrimiento de skills corre antes de que terminen los hooks
#    SessionStart; reloadSkills:true fuerza el re-escaneo, asi lo que trajo el
#    pull queda usable en esta sesion. Solo si el pull movio HEAD.
# Todo el cuerpo va en main() y la ultima linea es `main "$@"; exit`: bash lee un
# script de a trozos, y este mismo pull puede reescribir el archivo mientras corre
# (sesiones-paralelas-repos-compartidos, punto 8).

main() {
    # El repo es el dueño del script, no CLAUDE_PROJECT_DIR: una sesion que se
    # mudo de carpeta o que abrio en una subcarpeta conserva su carpeta de partida
    # en esa variable (2026-11-18 a 21: 8 caidas con exit 127 en clear y compact).
    # Por lo mismo cada repo lo registra con ruta absoluta en su settings.json.
    REPO=$(cd "$(dirname "$0")/../.." 2>/dev/null && pwd) || exit 0
    cd "$REPO" || exit 0

    MSG=""
    RELOAD=0
    HEAD_BEFORE=$(git rev-parse HEAD 2>/dev/null)

    if [ -f .git/MERGE_HEAD ]; then
        MSG="ADVERTENCIA: $REPO tiene un merge a medias (existe .git/MERGE_HEAD) y no se hizo git pull. Revisar con 'git status': terminarlo con 'git commit' si no quedan conflictos, o deshacerlo con 'git merge --abort'. No cerrar la sesion antes: el auto-commit de cierre lo commitearia tal cual."
    else
        PULL_OUTPUT=$(GIT_TERMINAL_PROMPT=0 timeout 30 git -c http.lowSpeedLimit=1000 -c http.lowSpeedTime=30 pull --ff-only </dev/null 2>&1)
        PULL_EXIT=$?
        if [ "$PULL_EXIT" -ne 0 ]; then
            case "$PULL_OUTPUT" in
                *"Not possible to fast-forward"*|*"diverg"*|*"divergentes"*|*"avance r"*)
                    QUE="la rama local y la remota divergieron (hay commits en los dos lados). No se mezclo nada. Resolver a mano: 'git pull --no-rebase' y, si hay conflictos, corregirlos y commitear antes de seguir." ;;
                *"index.lock"*)
                    QUE="otra sesion o proceso tiene tomado el indice de git (index.lock). Reintentar en un rato con 'git pull --ff-only'; no borrar el lock mientras otra sesion trabaje en este repo." ;;
                *"no tracking information"*|*"no hay informaci"*)
                    QUE="la rama actual no tiene rama remota de seguimiento. Configurarla con 'git branch --set-upstream-to=origin/<rama>' si corresponde." ;;
                *"would be overwritten"*|*"seran sobrescritos"*|*"sobrescritos"*)
                    QUE="hay cambios locales sin commitear en archivos que el pull traeria. Commitearlos (o apartarlos) y repetir 'git pull --ff-only'." ;;
                *)
                    if [ "$PULL_EXIT" -eq 124 ]; then
                        QUE="la red no respondio en 30 s (sin conexion o GitHub lento). El repo quedo como estaba; nada que arreglar, se actualiza en la proxima sesion o con 'git pull --ff-only'."
                    else
                        QUE="revisar la salida de git de abajo antes de seguir."
                    fi ;;
            esac
            MSG="ADVERTENCIA: git pull no se hizo en $REPO (codigo $PULL_EXIT): $QUE

$PULL_OUTPUT"
        fi
    fi

    LOCAL_HOOKS=$(git config --local --get core.hooksPath 2>/dev/null)
    if [ -z "$LOCAL_HOOKS" ]; then
        if [ -f .githooks/pre-commit ]; then
            git config core.hooksPath .githooks
        fi
    elif [ "$LOCAL_HOOKS" != ".githooks" ]; then
        MSG="${MSG:+$MSG

}AVISO: core.hooksPath de $REPO apunta a '$LOCAL_HOOKS' y no a .githooks, asi que no corren los hooks de git del repo (pre-commit, gitleaks). Si no es a proposito: 'git config core.hooksPath .githooks'."
    fi

    HEAD_AFTER=$(git rev-parse HEAD 2>/dev/null)
    if [ -n "$HEAD_BEFORE" ] && [ "$HEAD_BEFORE" != "$HEAD_AFTER" ]; then
        RELOAD=1
    fi

    if [ -z "$MSG" ] && [ "$RELOAD" -eq 0 ]; then
        exit 0
    fi

    export HOOK_MSG="$MSG"
    export HOOK_RELOAD="$RELOAD"
    python -c "
import json, os
msg = os.environ.get('HOOK_MSG', '')
hso = {'hookEventName': 'SessionStart'}
out = {'hookSpecificOutput': hso}
if msg:
    out['systemMessage'] = msg
    hso['additionalContext'] = msg
if os.environ.get('HOOK_RELOAD') == '1':
    hso['reloadSkills'] = True
print(json.dumps(out))
" || { [ -n "$MSG" ] && printf '%s\n' "$MSG"; }
    exit 0
}

main "$@"; exit
