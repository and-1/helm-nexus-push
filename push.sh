#!/usr/bin/env bash

set -ueo pipefail

usage() {
cat << EOF
Push Helm Chart to Nexus repository

This plugin provides ability to push a Helm Chart directory or package to a
remote Nexus Helm repository.

Usage:
  helm nexus-push [repo] login [flags]        Setup login information for repo
  helm nexus-push [repo] logout [flags]       Remove login information for repo
  helm nexus-push [repo] [CHART] [flags]      Pushes chart to repo

Flags:
  -u, --username string                 Username for authenticated repo (assumes anonymous access if unspecified)
  -p, --password string                 Password for authenticated repo (prompts if unspecified and -u specified)
EOF
}

declare REPO_USER=""
declare PASS=""

declare -a POSITIONAL_ARGS=()
while [[ $# -gt 0 ]]
do
    case "$1" in
        -h|--help)
            usage
            exit 0
            ;;
        -u|--username)
            if [[ -z "${2:-}" ]]; then
                echo "Must specify username!"
                echo "---"
                usage
                exit 1
            fi
            shift
            REPO_USER=$1
            ;;
        -p|--password)
            if [[ -n "${2:-}" ]]; then
                shift
                PASS=$1
            else
                PASS=
            fi
            ;;
        *)
            POSITIONAL_ARGS+=("$1")
            ;;
   esac
   shift
done
[[ ${#POSITIONAL_ARGS[@]} -ne 0 ]] && set -- "${POSITIONAL_ARGS[@]}" # restore positional parameters

if [[ $# -lt 2 ]]; then
  echo "Missing arguments!"
  echo "---"
  usage
  exit 1
fi

indent() { sed 's/^/  /'; }

declare REPO=$1
declare REPO_URL="$(helm repo list | grep "^$REPO\ " | awk '{print $2}')/"
declare REPO_AUTH_FILE="$(helm home)/repository/auth.$REPO"

if [[ -z "$REPO_URL" ]]; then
    echo "Invalid repo specified!  Must specify one of these repos..."
    helm repo list
    echo "---"
    usage
    exit 1
fi

declare CMD
declare AUTH
declare CHART

case "$2" in
    login)
        if [[ -z "$REPO_USER" ]]; then
            read -p "Username: " REPO_USER
        fi
        if [[ -z "$PASS" ]]; then
            read -s -p "Password: " PASS
            echo
        fi
        echo "$REPO_USER:$PASS" > "$REPO_AUTH_FILE"
        ;;
    logout)
        rm -f "$REPO_AUTH_FILE"
        ;;
    *)
        CMD=push
        CHART=$2

        if [[ -z "$REPO_USER" ]] || [[ -z "$PASS" ]]; then
            if [[ -f "$REPO_AUTH_FILE" ]]; then
                echo "Using cached login creds..."
                AUTH="$(cat $REPO_AUTH_FILE)"
            else
                if [[ -z "$REPO_USER" ]]; then
                    read -p "Username: " REPO_USER
                fi
                if [[ -z "$PASS" ]]; then
                    read -s -p "Password: " PASS
                    echo
                fi
                AUTH="$REPO_USER:$PASS"
            fi
        fi

        if [[ -d "$CHART" ]]; then
            CHART_PACKAGE="$(helm package -u "$CHART" | tail -n1 | cut -d":" -f2 | tr -d '[:space:]')"
        else
            CHART_PACKAGE="$CHART"
        fi

        echo "Pushing $CHART to repo $REPO_URL..."
        curl -is -u "$AUTH" "$REPO_URL" --upload-file "$CHART_PACKAGE" | indent
        if [[ -d "$CHART" ]]; then
          rm -f $CHART_PACKAGE
        fi
        echo "Done"
        ;;
esac

exit 0
