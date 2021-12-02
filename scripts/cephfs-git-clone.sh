#!/bin/bash

set -e

MAX_MDS=$(< linodes jq --raw-output 'map(select(.label | startswith("mds"))) | length')
MAX_MDS=$((MAX_MDS-1)) # leave one for standby
NUM_CLIENTS=$(< linodes jq --raw-output 'map(select(.label | startswith("client"))) | length')

TEST=kernel

###

# may be necessary for ansible with >25 forks
ulimit -n 65536 || true

LOG=$(date +OUTPUT-%Y%m%d-%H:%M)
EXPERIMENT=$(date +experiment-%Y%m%d-%H:%M)
RESULTS=/results/

source ansible-env.bash

function run {
  printf '%s\n' "$*" >&2
  "$@"
}

function ssh {
  /usr/bin/ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o PreferredAuthentications=publickey "$@"
}

function scp {
  /usr/bin/scp -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o PreferredAuthentications=publickey "$@"
}

function nclients {
  n="$1"
  max="$2"
  if [ -z "$max" ]; then
    max="$n"
  fi
  for ((i = 1; i <= n && i <= max; i++)); do
    if [[ $i > 1 ]]; then
      printf ' '
    fi
    printf "client-%03d" "$((i))"
  done
}

function pretest {
  local where="$1"
  local who="$2"
  run mkdir -p "$where"
  run do_playbook playbooks/cephfs-pre-test.yml
  run ans -m shell -a 'df -h /perf/' "$who" &> "${where}/pre-df"
  run date +%s > "${where}/start"
}
function posttest {
  local where="$1"
  local who="$2"
  run ans -m shell -a 'df -h /perf/' "$who" &> "${where}/post-df"
  run date +%s > "${where}/end"
  run do_playbook --extra-vars instance="${where}" playbooks/cephfs-post-test.yml
}

function do_bootstrap {
  # Setup a legit clone of linus' tree
  D="$1/bootstrap/"
  run mkdir -p "$D"
  run ans --module-name=copy --args="src=misc/bootstrap-clone-kernel-source.sh dest=/root/ owner=root group=root mode=755" client-000
  pretest "$D" client-000
  run ans -m shell -a "/root/bootstrap-clone-kernel-source.sh" client-000
  posttest "$D" client-000
  # Now create 100 other distinct clones of that for future tests
  D="$1/clone/"
  ans -m shell -a "ceph fs set perf max_mds $MAX_MDS" mon-000
  run ans --module-name=copy --args="src=misc/clone-kernel-sources.sh dest=/root/ owner=root group=root mode=755" clients
  pretest "$D" clients
  run ans -m shell -a "/root/clone-kernel-sources.sh 4 $MAX_MDS" "$(nclients 25)"
  posttest "$D" clients
  ans -m shell -a "ceph fs set perf max_mds 1" mon-000
}

function do_test {
  local exp="$1"
  local i="$2"
  local max_mds="$3"
  local count="$4"
  local instance="$(printf 'max_mds:%02d/count:%02d/i:%02d/' "$max_mds" "$count" "$i")"
  local D="${exp}/results/${instance}"
  run mkdir -p "$D"
  printf '%d\n' "$i" > "$D"/i
  printf '%d\n' "$max_mds" > "$D"/max_mds
  printf '%d\n' "$count" > "$D"/count
  printf '%s\n' "$instance" > "$D"/instance
  printf '%s\n' "$(date +%Y%m%d-%H:%M)" > "$D"/date
  {
    ans -m shell -a "ceph fs set perf max_mds $max_mds" mon-000
    run ans --module-name=copy --args="src=misc/test-clone-rm-kernel.sh dest=/root/ owner=root group=root mode=755" clients
    pretest "$D" clients
    run ans -m shell -a "/root/test-clone-rm-kernel.sh --distributed $(( count > NUM_CLIENTS ? count/NUM_CLIENTS : 1 ))" "$(nclients "$count" NUM_CLIENTS)"
    posttest "$D" clients
  } |& tee "$D"/log
}

function main {
  exp="${RESULTS}/${EXPERIMENT}"
  mkdir -p -- "$exp"

  run cp -av -- ansible_inventory linodes cluster.json "$exp/"

  {
    run do_playbook playbooks/cephfs-setup.yml

    run do_playbook playbooks/cephfs-reset.yml

    run do_bootstrap "$exp"

    for ((max_mds = 1; max_mds <= MAX_MDS; ++max_mds)); do
      for count in 1 4 16 64 128; do
        for ((i = 0; i < 1; i++)); do
          run do_test "$exp" "$i" "$max_mds" "$count" || true
        done
      done
    done
  } |& tee "${exp}/experiment.log"
}

ARGUMENTS='--options e:,h,l:,r: --long experiment:,help,results:'
NEW_ARGUMENTS=$(getopt $ARGUMENTS -- "$@")
eval set -- "$NEW_ARGUMENTS"

function usage {
    printf "%s: [--experiment <experiment>]\n" "$0"
}

while [ "$#" -ge 0 ]; do
    case "$1" in
        -e|--experiment)
            shift
            EXPERIMENT="$1"
            shift
            ;;
        -h|--help)
            usage
            exit
            ;;
        --metadata-pg)
            shift
            METADATA_PG="$1"
            shift
            ;;
        --data-pg)
            shift
            DATA_PG="$1"
            shift
            ;;
        -r|--results)
            shift
            RESULTS="$1"
            shift
            ;;
        --)
            shift
            break
            ;;
    esac
done

main "$@"
