#!/usr/bin/env bash

# This script sets up and runs the rke2 deployment scenario for Sylva CI.
# The executed scripts are in https://gitlab.com/sylva-projects/sylva-core

set -eu -o pipefail

: "${SELF:=$(realpath $(dirname $0))}"
: "${CORE:=$(realpath $1)}"
: "${WORK:=$(mktemp -d /var/tmp/sylva-ci-XXXXX)}"

trap "rm --preserve-root -rf '$WORK'" ERR EXIT

# Prepare working directory by copying necessary files
tar --mode=u+rw,go+r -cf- -C "$CORE/" . | tar -xf- -C "$WORK/"
tar --mode=u+rw,go+r -cf- -C "$SELF/mgmt/" . | tar -xf- -C "$WORK/environment-values/"
tar --mode=u+rw,go+r -cf- -C "$SELF/wkld/" . | tar -xf- -C "$WORK/environment-values/workload-clusters/"

cd "$WORK/"

# Execute sylva core scripts

(./bootstrap.sh ./environment-values/my-rke2-capone)

(./apply-workload-cluster.sh ./environment-values/workload-clusters/my-rke2-capone)

(./apply.sh ./environment-values/my-rke2-capone)

(./apply-workload-cluster.sh ./environment-values/workload-clusters/my-rke2-capone)
