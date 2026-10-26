#!/usr/bin/env bash
set -euo pipefail

SOCK=${DOCKER_SOCK:-/var/run/docker.sock}
BODY=$(mktemp)
trap 'rm -f "$BODY"' EXIT
HTTP_CODE=''

usage() {
    echo "Usage : $0 {ls|run NOM IMAGE [PORT_HOTE:PORT_CONTENEUR]|exec NOM COMMANDE...|rm NOM|clean}" >&2
    exit 1
}

api() {
    local method=$1 path=$2 data=${3:-}
    local args=(-sS --unix-socket "$SOCK" -X "$method" -o "$BODY" -w '%{http_code}')
    if [[ -n "$data" ]]; then
        args+=(-H 'Content-Type: application/json' --data "$data")
    fi
    HTTP_CODE=$(curl "${args[@]}" "http://localhost$path")
}

http_error() {
    local message
    message=$(jq -r '.message // .errorDetail.message // .error // empty' "$BODY" 2>/dev/null || true)
    [[ -n "$message" ]] || message='Réponse inattendue de Docker'
    echo "Erreur HTTP $HTTP_CODE : $message" >&2
    exit 1
}

expect_http() {
    local expected
    for expected in "$@"; do
        [[ "$HTTP_CODE" == "$expected" ]] && return 0
    done
    http_error
}

encode() {
    jq -nr --arg value "$1" '$value | @uri'
}

inspect_tp() {
    local name=$1
    api GET "/containers/$(encode "$name")/json"
    if [[ "$HTTP_CODE" == 404 ]]; then
        return 1
    fi
    expect_http 200
    if ! jq -e '.Config.Labels.tp == "api-rest"' "$BODY" >/dev/null; then
        echo "Refus : '$name' ne porte pas le label tp=api-rest" >&2
        exit 1
    fi
    return 0
}

remove_tp() {
    local name=$1 running
    if ! inspect_tp "$name"; then
        echo "Conteneur '$name' déjà absent."
        return 0
    fi
    running=$(jq -r '.State.Running' "$BODY")
    if [[ "$running" == true ]]; then
        api POST "/containers/$(encode "$name")/stop?t=5"
        expect_http 204 304
    fi
    api DELETE "/containers/$(encode "$name")"
    expect_http 204
    echo "Conteneur '$name' supprimé."
}

case "${1:-}" in
    ls)
        [[ $# -eq 1 ]] || usage
        filters=$(jq -nc '{label:["tp=api-rest"]}')
        api GET "/containers/json?all=true&filters=$(encode "$filters")"
        expect_http 200
        jq -r '.[] | [
            (.Names[0] | ltrimstr("/")),
            .State,
            .Image,
            ([.Ports[]? | select(.PublicPort != null) |
              "\(.PublicPort):\(.PrivatePort)"] | unique | join(","))
        ] | @tsv' "$BODY"
        ;;

    run)
        [[ $# -eq 3 || $# -eq 4 ]] || usage
        name=$2
        image=$3
        port=${4:-}

        if [[ ! "$name" =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]*$ ]]; then
            echo "Nom invalide : lettres, chiffres, _, - et . uniquement." >&2
            exit 1
        fi

        host_port=''
        container_port=''
        if [[ -n "$port" ]]; then
            if [[ ! "$port" =~ ^([0-9]{1,5}):([0-9]{1,5})$ ]]; then
                echo "Port invalide : format PORT_HOTE:PORT_CONTENEUR." >&2
                exit 1
            fi
            host_port=${BASH_REMATCH[1]}
            container_port=${BASH_REMATCH[2]}
            if (( 10#$host_port < 1 || 10#$host_port > 65535 ||
                  10#$container_port < 1 || 10#$container_port > 65535 )); then
                echo "Les ports doivent être compris entre 1 et 65535." >&2
                exit 1
            fi
        fi

        api GET "/images/$(encode "$image")/json"
        case "$HTTP_CODE" in
            200) ;;
            404)
                echo "Téléchargement de l'image '$image'..." >&2
                api POST "/images/create?fromImage=$(encode "$image")"
                expect_http 200

                if ! jq -se 'all(.[]; (.error? == null) and (.errorDetail? == null))' "$BODY" >/dev/null; then
                    echo "Erreur pendant le téléchargement de l'image :" >&2
                    jq -r 'select(.error != null) | .error' "$BODY" >&2 || true
                    exit 1
                fi
                ;;
            *) http_error ;;
        esac

        data=$(jq -n --arg image "$image" \
                     --arg host "$host_port" \
                     --arg port "$container_port" '
            {Image: $image, Labels: {"tp": "api-rest"}}
            | if $host != "" then
                . + {
                    ExposedPorts: {($port + "/tcp"): {}},
                    HostConfig: {PortBindings: {
                        ($port + "/tcp"): [{HostPort: $host}]
                    }}
                }
              else . end
        ')

        api POST "/containers/create?name=$(encode "$name")" "$data"
        expect_http 201
        id=$(jq -er '.Id' "$BODY")
        api POST "/containers/$id/start"
        expect_http 204
        echo "${id:0:12}"
        ;;

    exec)
        [[ $# -ge 3 ]] || usage
        name=$2
        shift 2
        if ! inspect_tp "$name"; then
            echo "Conteneur '$name' introuvable." >&2
            exit 1
        fi
        if [[ $(jq -r '.State.Running' "$BODY") != true ]]; then
            echo "Le conteneur '$name' n'est pas en cours d'exécution." >&2
            exit 1
        fi

        data=$(jq -nc '{
            Cmd: $ARGS.positional,
            AttachStdout: true,
            AttachStderr: true,
            Tty: true
        }' --args -- "$@")

        api POST "/containers/$(encode "$name")/exec" "$data"
        expect_http 201
        exec_id=$(jq -er '.Id' "$BODY")

        api POST "/exec/$exec_id/start" '{"Detach":false,"Tty":true}'
        expect_http 200
        cat "$BODY"

        api GET "/exec/$exec_id/json"
        expect_http 200
        exit_code=$(jq -er '.ExitCode | numbers' "$BODY") || {
            echo "Impossible de lire le code de sortie de la commande." >&2
            exit 1
        }
        exit "$exit_code"
        ;;

    rm)
        [[ $# -eq 2 ]] || usage
        remove_tp "$2"
        ;;

    clean)
        [[ $# -eq 1 ]] || usage
        filters=$(jq -nc '{label:["tp=api-rest"]}')
        api GET "/containers/json?all=true&filters=$(encode "$filters")"
        expect_http 200
        ids=$(jq -r '.[].Id' "$BODY")
        if [[ -z "$ids" ]]; then
            echo 'Aucun conteneur du TP à supprimer.'
        else
            while IFS= read -r id; do
                [[ -n "$id" ]] && remove_tp "$id"
            done <<< "$ids"
        fi
        ;;

    *) usage ;;
esac
