#!/bin/sh
#
# Copyright 2024 Joseph Kroesche
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the “Software”), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
#
# many parts of this script are lifted from borgbackup help docs

usage()
{
    echo ""
    echo "Usage:"
    echo "  borg-backup -b SET_NAME [-n compact] [-n prune]"
    echo "  borg-backup -t SET_NAME"
    echo "  borg-backup -l"
    echo "  borg-backup -h"
    echo ""
    echo "Options:"
    echo "  -h            show help"
    echo "  -l            list available backup set configurations"
    echo "  -b SET_NAME   backup the configuration named SET_NAME"
    echo "  -t SET_NAME   dry-run backup of SET_NAME"
    echo "  -n prune      skip prune operation"
    echo "  -n compact    skip compact operation"
    echo ""
}

info()
{
    printf "%s %s\n" "$( date )" "$*" >&2;
}

list()
{
    echo ""
    echo "Available backup configurations"
    echo "-------------------------------"
    for cfg in borg-set-*
    do
        . ./$cfg
        setname=$(echo $cfg | sed -E "s/borg-set-(.*)\.cfg/\1/")
        printf "%-16s %s" "${setname}" "${BACKUP_SET_DESCRIPTION}"
    done
    echo ""
}

trap 'echo $( date ) Backup interrupted >&2; exit 2' INT TERM

info "borg-backup script started"

# switch to script directory
cd "$(dirname "$0")"

# initialize prune and compact defaults
doprune=1
docompact=1

# process command line
# if no options are passed at all, then show help
if [ $# == 0 ]
then
    usage
    exit 0
fi

# support --help since that is common
if [ "$1" == "--help" ]
then
    usage
    exit 0
fi

# otherwise, process the options
# this does not do a lot of cross checking of options so it is possible
# to specify nonsense set of options
while getopts ":lhb:t:n:" opt; do
    case ${opt} in
        h)
            usage
            exit 0
            ;;
        l)
            list
            exit 0
            ;;
        b)
            if [ "$action" == "test" ]
            then
                info "you cannot request both -b and -t"
                exit 1
            fi
            action="backup"
            setname=${OPTARG}
            info "requested backup of set: ${setname}"
            ;;
        t)
            if [ "$action" == "backup" ]
            then
                info "you cannot request both -b and -t"
                exit 1
            fi
            action="test"
            setname=${OPTARG}
            info "requested dry-run of set: ${setname}"
            ;;
        n)
            if [ "${OPTARG}" == "prune" ]
            then
                doprune=0
                info "requested skip pruning"
            elif [ "${OPTARG}" == "compact" ]
            then
                docompact=0
                info "requested skip compacting"
            fi
            ;;
        :)
            echo "Option -${OPTARG} requires an argument"
            exit 1
            ;;
        ?)
            echo "Invalid option: -${OPTARG}"
            exit 1
            ;;
    esac
done

# determine command action
# --stats and --dry-run are not compatible switches for borg
if [ "$action" == "backup" ]
then
    action_switch="--stats"
    filter="--filter AME"
elif [ "$action" == "test" ]
then
    action_switch="--dry-run"
    filter=""
else
    info "bad command: $action"
    usage
    exit 1
fi

info "using set name: ${setname}, action: ${action}"

# determine configuration file names
#
# repo_config contains the definitions of the BORG_REPO env variables.
# It should define BORG_REPO and BORG_PASSPHRASE or BORG_PASSCOMMAND
# these should be exports so the file can be sourced
#
repo_config_file="borg-repo.cfg"        # BORG_REPO, etc

# common exclude is a list of files/folders to exclude using the borg
# pattern style. one exclusion per line in the file
#
common_exclude_file="exclude-common.txt"

# set_config is the config file for the specific backup set
# it is of the form:
#
# BACKUP_CUSTOM_FLAGS="--exclude '*/pattern1' --exclude '*/pattern2' <other custom flags/configs>"
# BACKUP_SOURCE_PATHS="<backup-path1> <backuppath2>"
#
# where:
# * variable values should be in quotes
# * make sure there is a space between switches
# * BACKUP_CUSTOM_FLAGS is mostly --exclude patterns but other borg
# * flags can be added
# * BACKUP_CUSTOM_FLAGS can be empty
# * common exclude paths do not need to be repeated, only extra includes for
#   this specific backup set
# * BACKUP_SOURCE_PATHS must have at least one path, but can have more than one
# * the file can have comments on lines by themselves
#
set_config_file="borg-set-${setname}.cfg"

# make sure backup set is valid based on existence of a config file
if [ -f "${set_config_file}" ]
then
    # read in (source) the custom backup variables
    . "./${set_config_file}"
else
    info "No config file found for backup set: ${set_config_file}"
    exit 1
fi

info "BACKUP_CUSTOM_FLAGS ..."
info ${BACKUP_CUSTOM_FLAGS}
info "BACKUP_SOURCE_PATHS ..."
info ${BACKUP_SOURCE_PATHS}

# validate and source the repo credentials
if [ -f "${repo_config_file}" ]
then
    . "./${repo_config_file}"
else
    info "No repo config file found: ${repo_config_file}"
    exit 1
fi

info "BORG_REPO ..."
info "${BORG_REPO}"
info "BORG_PASS... is not shown for security"

# to get quoting, and paths with spaces being included from the 'set' files,
# I had to use xargs to get all the command line args expanded correctly to be
# passed to borg. there is probably a better way to do this, but it works on
# my mac
#
# assemble all the common and custom command line args into one variable
BORG_CLI_ARGS="create
--verbose --list --show-rc --compression zstd,9 --exclude-caches --exclude-nodump
${filter} ${action_switch}
--exclude-from ${common_exclude_file}
${BACKUP_CUSTOM_FLAGS} ::{hostname}-${setname}-{now} ${BACKUP_SOURCE_PATHS}"

# show what will be called
info "BORG_CLI_ARGS:"
info $BORG_CLI_ARGS

info "Starting backup: ${setname}"
# use xargs to expand args and pass to borg. this seems to work
echo $BORG_CLI_ARGS | xargs borg

# if it was a test run, just exit here
if [ "$action" == "test" ]
then
    info "End of test run"
    exit 0
fi

backup_exit=$?

if [ $doprune == 1 ]
then
    info "Pruning backup"

    borg prune --list --glob-archives "{hostname}-${setname}-*" --show-rc    \
        --keep-daily 7                  \
        --keep-weekly 4                 \
        --keep-monthly 6
    prune_exit=$?
else
    info "skipping prune"
    prune_exit=0
fi

if [ $docompact == 1 ]
then
    info "Compacting backup"

    borg compact
    compact_exit=$?
else
    info "skipping compact"
    compact_exit=0
fi

global_exit=$(( backup_exit > prune_exit ? backup_exit : prune_exit ))
global_exit=$(( compact_exit > global_exit ? compact_exit : global_exit ))

if [ ${global_exit} -eq 0 ]; then
    info "Backup, Prune, and Compact finished successfully"
elif [ ${global_exit} -eq 1 ]; then
    info "Backup, Prune, and/or Compact finished with warnings"
else
    info "Backup, Prune, and/or Compact finished with errors"
fi

exit ${global_exit}
