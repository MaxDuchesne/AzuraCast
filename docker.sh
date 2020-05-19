#!/usr/bin/env bash
# shellcheck disable=SC2145,SC2178,SC2120,SC2162

# Functions to manage .env files
__dotenv=
__dotenv_file=
__dotenv_cmd=.env

.env() {
    REPLY=()
    [[ $__dotenv_file || ${1-} == -* ]] || .env.--file .env || return
    if declare -F -- ".env.${1-}" >/dev/null; then
        .env."$@"
        return
    fi
    .env --help >&2
    return 64
}

.env.-f() { .env.--file "$@"; }

.env.get() {
    .env::arg "get requires a key" "$@" &&
        [[ "$__dotenv" =~ ^(.*(^|$'\n'))([ ]*)"$1="(.*)$ ]] &&
        REPLY=${BASH_REMATCH[4]%%$'\n'*} && REPLY=${REPLY%"${REPLY##*[![:space:]]}"}
}

.env.parse() {
    local line key
    while IFS= read -r line; do
        line=${line#"${line%%[![:space:]]*}"} # trim leading whitespace
        line=${line%"${line##*[![:space:]]}"} # trim trailing whitespace
        if [[ ! "$line" || "$line" == '#'* ]]; then continue; fi
        if (($#)); then
            for key; do
                if [[ $key == "${line%%=*}" ]]; then
                    REPLY+=("$line")
                    break
                fi
            done
        else
            REPLY+=("$line")
        fi
    done <<<"$__dotenv"
    ((${#REPLY[@]}))
}

.env.export() { ! .env.parse "$@" || export "${REPLY[@]}"; }

.env.set() {
    .env::file load || return
    local key saved=$__dotenv
    while (($#)); do
        key=${1#+}
        key=${key%%=*}
        if .env.get "$key"; then
            REPLY=()
            if [[ $1 == +* ]]; then
                shift
                continue # skip if already found
            elif [[ $1 == *=* ]]; then
                __dotenv=${BASH_REMATCH[1]}${BASH_REMATCH[3]}$1$'\n'${BASH_REMATCH[4]#*$'\n'}
            else
                __dotenv=${BASH_REMATCH[1]}${BASH_REMATCH[4]#*$'\n'}
                continue # delete all occurrences
            fi
        elif [[ $1 == *=* ]]; then
            __dotenv+="${1#+}"$'\n'
        fi
        shift
    done
    [[ $__dotenv == "$saved" ]] || .env::file save
}

.env.puts() { echo "${1-}" >>"$__dotenv_file" && __dotenv+="$1"$'\n'; }

.env.generate() {
    .env::arg "key required for generate" "$@" || return
    .env.get "$1" && return || REPLY=$("${@:2}") || return
    .env::one "generate: ouptut of '${*:2}' has more than one line" "$REPLY" || return
    .env.puts "$1=$REPLY"
}

.env.--file() {
    .env::arg "filename required for --file" "$@" || return
    __dotenv_file=$1
    .env::file load || return
    (($# < 2)) || .env "${@:2}"
}

.env::arg() { [[ "${2-}" ]] || {
    echo "$__dotenv_cmd: $1" >&2
    return 64
}; }

.env::one() { [[ "$2" != *$'\n'* ]] || .env::arg "$1"; }

.env::file() {
    local REPLY=$__dotenv_file
    case "$1" in
    load)
        __dotenv=
        ! [[ -f "$REPLY" ]] || __dotenv="$(<"$REPLY")"$'\n' || return
        ;;
    save)
        if [[ -L "$REPLY" ]] && declare -F -- realpath.resolved >/dev/null; then
            realpath.resolved "$REPLY"
        fi
        { [[ ! -f "$REPLY" ]] || cp -p "$REPLY" "$REPLY.bak"; } &&
            printf %s "$__dotenv" >"$REPLY.bak" && mv "$REPLY.bak" "$REPLY"
        ;;
    esac
}
.env.-h() { .env.--help "$@"; }
.env.--help() {
    echo "Usage:
  $__dotenv_cmd [-f|--file FILE] COMMAND [ARGS...]
  $__dotenv_cmd -h|--help

Options:
  -f, --file FILE          Use a file other than .env

Read Commands:
  get KEY                  Get raw value of KEY (or fail)
  parse [KEY...]           Get trimmed KEY=VALUE lines for named keys (or all)
  export [KEY...]          Export the named keys (or all) in shell format

Write Commands:
  set [+]KEY[=VALUE]...    Set or unset values (in-place w/.bak); + sets default
  puts STRING              Append STRING to the end of the file
  generate KEY [CMD...]    Set KEY to the output of CMD unless it already exists;
                           return the new or existing value."
}

__dotenv() {
    set -eu
    __dotenv_cmd=${0##*/}
    .env.export() {
        .env.parse "$@" || return 0
        printf 'export %q\n' "${REPLY[@]}"
        REPLY=()
    }
    .env "$@" || return $?
    ${REPLY[@]+printf '%s\n' "${REPLY[@]}"}
}

# This is a general-purpose function to ask Yes/No questions in Bash, either
# with or without a default answer. It keeps repeating the question until it
# gets a valid answer.
ask() {
    # https://djm.me/ask
    local prompt default reply

    while true; do

        if [[ "${2:-}" == "Y" ]]; then
            prompt="Y/n"
            default=Y
        elif [[ "${2:-}" == "N" ]]; then
            prompt="y/N"
            default=N
        else
            prompt="y/n"
            default=
        fi

        # Ask the question (not using "read -p" as it uses stderr not stdout)
        echo -n "$1 [$prompt] "

        read reply

        # Default?
        if [[ -z "$reply" ]]; then
            reply=${default}
        fi

        # Check if the reply is valid
        case "$reply" in
        Y* | y*) return 0 ;;
        N* | n*) return 1 ;;
        esac

    done
}

#
# Configure the ports used by AzuraCast.
# Usage: ./docker.sh setup_ports
#
setup_ports() {
    AZURACAST_HTTP_PORT=80
    read -p "Port to use for HTTP connections? [80]:" INPUT
    AZURACAST_HTTP_PORT="${INPUT:-$AZURACAST_HTTP_PORT}"

    AZURACAST_HTTPS_PORT=443
    read -p "Port to use for HTTPS connections? [443]:" INPUT
    AZURACAST_HTTPS_PORT="${INPUT:-$AZURACAST_HTTPS_PORT}"

    AZURACAST_SFTP_PORT=2022
    read -p "Port to use for SFTP connections? [2022]:" INPUT
    AZURACAST_SFTP_PORT="${INPUT:-$AZURACAST_SFTP_PORT}"

    .env --file .env put AZURACAST_HTTP_PORT="${AZURACAST_HTTP_PORT}" \
        AZURACAST_HTTPS_PORT="${AZURACAST_HTTPS_PORT}" \
        AZURACAST_SFTP_PORT="${AZURACAST_SFTP_PORT}"
}

#
# Configure the settings used by LetsEncrypt.
#
setup_letsencrypt() {
    read -p "Domain name (example.com) or names (example.com,foo.bar) to use with LetsEncrypt:" INPUT
    LETSENCRYPT_HOST="${INPUT:-""}"

    read -p "Optional e-mail address for expiration updates:" INPUT
    LETSENCRYPT_EMAIL="${INPUT:-""}"

    .env --file .env put LETSENCRYPT_HOST="${LETSENCRYPT_HOST}" \
        LETSENCRYPT_EMAIL="${LETSENCRYPT_EMAIL}"
}

#
# Run the initial installer of Docker and AzuraCast.
# Usage: ./docker.sh install
#
install() {
    if [[ ! $(command -v curl) ]]; then
        echo "cURL does not appear to be installed."
        echo "Install curl using your host's package manager,"
        echo "then continue installing using this script."
        exit 1
    fi

    if [[ $(command -v docker) && $(docker --version) ]]; then
        echo "Docker is already installed! Continuing..."
    else
        if ask "Docker does not appear to be installed. Install Docker now?" Y; then
            curl -fsSL get.docker.com -o get-docker.sh
            sh get-docker.sh
            rm get-docker.sh

            if [[ $EUID -ne 0 ]]; then
                sudo usermod -aG docker "$(whoami)"

                echo "You must log out or restart to apply necessary Docker permissions changes."
                echo "Restart, then continue installing using this script."
                exit
            fi
        fi
    fi

    if [[ $(command -v docker-compose) && $(docker-compose --version) ]]; then
        echo "Docker Compose is already installed! Continuing..."
    else
        if ask "Docker Compose does not appear to be installed. Install Docker Compose now?" Y; then
            COMPOSE_VERSION=1.25.3

            if [[ $EUID -ne 0 ]]; then
                if [[ ! $(command -v sudo) ]]; then
                    echo "Sudo does not appear to be installed."
                    echo "Install sudo using your host's package manager,"
                    echo "then continue installing using this script."
                    exit 1
                fi

                sudo sh -c "curl -fsSL https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m) -o /usr/local/bin/docker-compose"
                sudo chmod +x /usr/local/bin/docker-compose
                sudo sh -c "curl -fsSL https://raw.githubusercontent.com/docker/compose/${COMPOSE_VERSION}/contrib/completion/bash/docker-compose -o /etc/bash_completion.d/docker-compose"
            else
                curl -fsSL https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m) -o /usr/local/bin/docker-compose
                chmod +x /usr/local/bin/docker-compose
                curl -fsSL https://raw.githubusercontent.com/docker/compose/${COMPOSE_VERSION}/contrib/completion/bash/docker-compose -o /etc/bash_completion.d/docker-compose
            fi
        fi
    fi

    if [[ ! -f .env ]]; then
        echo "Writing default .env file..."
        curl -fsSL https://raw.githubusercontent.com/AzuraCast/AzuraCast/master/sample.env -o .env
    fi

    if [[ ! -f azuracast.env ]]; then
        echo "Creating default AzuraCast settings file..."
        curl -fsSL https://raw.githubusercontent.com/AzuraCast/AzuraCast/master/azuracast.sample.env -o azuracast.env

        # Generate a random password and replace the MariaDB password with it.
        NEW_PASSWORD=$(
            tr </dev/urandom -dc _A-Z-a-z-0-9 | head -c"${1:-32}"
            echo
        )
        sed -i "s/azur4c457/${NEW_PASSWORD}/g" azuracast.env
    fi

    if [[ ! -f docker-compose.yml ]]; then
        echo "Retrieving default docker-compose.yml file..."
        curl -fsSL https://raw.githubusercontent.com/AzuraCast/AzuraCast/master/docker-compose.sample.yml -o docker-compose.yml
    fi

    if ask "Customize AzuraCast ports?" N; then
        setup_ports
    fi

    if ask "Set up LetsEncrypt?" N; then
        setup_letsencrypt
    fi

    docker-compose pull
    docker-compose run --user="azuracast" --rm web azuracast_install "$@"
    docker-compose up -d
    exit
}

#
# Update the Docker images and codebase.
# Usage: ./docker.sh update
#
update() {

    curl -fsSL https://raw.githubusercontent.com/AzuraCast/AzuraCast/master/docker-compose.sample.yml -o docker-compose.new.yml

    FILES_MATCH="$(
        cmp --silent docker-compose.yml docker-compose.new.yml
        echo $?
    )"
    UPDATE_NEW=0

    if [[ ${FILES_MATCH} -ne 0 ]]; then
        if ask "The docker-compose.yml file has changed since your version. Overwrite? This will overwrite any customizations you made to this file?" Y; then
            UPDATE_NEW=1
        fi
    fi

    if [[ ${UPDATE_NEW} -ne 0 ]]; then
        docker-compose -f docker-compose.new.yml pull
        docker-compose down

        cp docker-compose.yml docker-compose.backup.yml
        mv docker-compose.new.yml docker-compose.yml
    else
        rm docker-compose.new.yml

        docker-compose pull
        docker-compose down
    fi

    if [[ ! -f azuracast.env ]]; then
        curl -fsSL https://raw.githubusercontent.com/AzuraCast/AzuraCast/master/azuracast.sample.env -o azuracast.env
        echo "Default environment file loaded."
    fi

    docker volume rm azuracast_www_data
    docker volume rm azuracast_tmp_data
    docker volume rm azuracast_redis_data

    docker-compose run --user="azuracast" --rm web azuracast_update "$@"
    docker-compose up -d

    docker rmi "$(docker images | grep "none" | awk '/ / { print $3 }')" 2>/dev/null

    echo "Update complete!"
    exit
}

#
# Update this Docker utility script.
# Usage: ./docker.sh update-self
#
update-self() {
    curl -fsSL https://raw.githubusercontent.com/AzuraCast/AzuraCast/master/docker.sh -o docker.sh
    chmod a+x docker.sh

    echo "New Docker utility script downloaded."
    exit
}

#
# Run a CLI command inside the Docker container.
# Usage: ./docker.sh cli [command]
#
cli() {
    docker-compose run --user="azuracast" --rm web azuracast_cli "$@"
    exit
}

#
# Enter the bash terminal of the running web container.
# Usage: ./docker.sh bash
#
bash() {
    docker-compose exec --user="azuracast" web bash
    exit
}

#
# Back up the Docker volumes to a .tar.gz file.
# Usage:
# ./docker.sh backup [/custom/backup/dir/custombackupname.zip]
#
backup() {
    BACKUP_PATH=${1:-"./backup.tar.gz"}
    BACKUP_FILENAME=$(basename -- "$BACKUP_PATH")
    BACKUP_EXT="${BACKUP_FILENAME##*.}"
    shift

    MSYS_NO_PATHCONV=1 docker exec --user="azuracast" azuracast_web azuracast_cli azuracast:backup "/tmp/cli_backup.${BACKUP_EXT}" "$@"
    docker cp "azuracast_web:tmp/cli_backup.${BACKUP_EXT}" "${BACKUP_PATH}"
    MSYS_NO_PATHCONV=1 docker exec --user="azuracast" azuracast_web rm -f "/tmp/cli_backup.${BACKUP_EXT}"
    exit
}

#
# Restore an AzuraCast backup into Docker.
# Usage:
# ./docker.sh restore [/custom/backup/dir/custombackupname.zip]
#
restore() {
    BACKUP_PATH=${1:-"./backup.tar.gz"}
    BACKUP_FILENAME=$(basename -- "$BACKUP_PATH")
    BACKUP_EXT="${BACKUP_FILENAME##*.}"
    shift

    if [[ ! -f .env ]] || [[ ! -f azuracast.env ]]; then
        echo "AzuraCast hasn't been installed yet on this server."
        echo "You should run './docker.sh install' first before restoring."
        exit 1
    fi

    if [[ ! -f ${BACKUP_PATH} ]]; then
        echo "File '${BACKUP_PATH}' does not exist. Nothing to restore."
        exit 1
    fi

    if ask "Restoring will remove any existing AzuraCast installation data, replacing it with your backup. Continue?" Y; then
        docker-compose down -v
        docker-compose pull
        docker-compose up -d web
        docker cp "${BACKUP_PATH}" "azuracast_web:tmp/cli_backup.${BACKUP_EXT}"
        MSYS_NO_PATHCONV=1 docker exec --user="azuracast" azuracast_web azuracast_restore "/tmp/cli_backup.${BACKUP_EXT}" "$@"

        docker-compose down
        docker-compose up -d
    fi

    exit
}

#
# Restore the Docker volumes from a legacy backup format .tar.gz file.
# Usage:
# ./docker.sh restore [/custom/backup/dir/custombackupname.tar.gz]
#
restore-legacy() {
    APP_BASE_DIR=$(pwd)

    BACKUP_PATH=${1:-"./backup.tar.gz"}
    BACKUP_DIR=$(cd "$(dirname "$BACKUP_PATH")" && pwd)
    BACKUP_FILENAME=$(basename "$BACKUP_PATH")

    cd "$APP_BASE_DIR"

    if [ -f "$BACKUP_PATH" ]; then
        docker-compose down

        docker volume rm azuracast_db_data azuracast_influx_data azuracast_station_data
        docker volume create azuracast_db_data
        docker volume create azuracast_influx_data
        docker volume create azuracast_station_data

        docker run --rm -v "$BACKUP_DIR:/backup" \
            -v azuracast_db_data:/azuracast/db \
            -v azuracast_influx_data:/azuracast/influx \
            -v azuracast_station_data:/azuracast/stations \
            busybox tar zxvf "/backup/$BACKUP_FILENAME"

        docker-compose up -d
    else
        echo "File $BACKUP_PATH does not exist in this directory. Nothing to restore."
        exit 1
    fi

    exit
}

#
# DEVELOPER TOOL:
# Access the static console as a developer.
# Usage: ./docker.sh static [static_container_command]
#
static() {
    cd frontend
    docker-compose build
    docker-compose run --rm frontend "$@"
    exit
}

#
# DEVELOPER TOOL:
# Run the full test suite.
#
dev-tests() {
    dev-lint
    dev-phpstan
    dev-codeception
    exit
}

#
# DEVELOPER TOOL:
# Run linter across all PHP code in the app.
#
dev-lint() {
    docker-compose exec --user="azuracast" web composer phplint -- "$@"
}

#
# DEVELOPER TOOL:
# Run PHPStan for static analysis.
#
dev-phpstan() {
    docker-compose exec --user="azuracast" web composer phpstan -- "$@"
}

#
# DEVELOPER TOOL:
# Run codeception for unit testing.
#
dev-codeception() {
    docker-compose -f docker-compose.sample.yml -f docker-compose.testing.yml build web
    docker-compose -f docker-compose.sample.yml -f docker-compose.testing.yml run --user="azuracast" --rm web composer codeception -- "$@"
}

#
# Stop all Docker containers and remove related volumes.
# Usage: ./docker.sh uninstall
#
uninstall() {
    if ask "This operation is destructive and will wipe your existing Docker containers. Continue? [y/N] " N; then

        docker-compose down -v
        docker-compose rm -f
        docker volume prune -f

        echo "All AzuraCast Docker containers and volumes were removed."
        echo "To remove *all* Docker containers and volumes, run:"
        echo "  docker stop \$(docker ps -a -q)"
        echo "  docker rm \$(docker ps -a -q)"
        echo "  docker volume prune -f"
        echo ""
    fi

    exit
}

#
# Create and link a LetsEncrypt SSL certificate.
# Usage: ./docker.sh letsencrypt-create
#
letsencrypt-create() {
    setup_letsencrypt

    docker-compose stop web
    docker-compose rm web
    docker-compose up -d
    exit
}

"$@"
