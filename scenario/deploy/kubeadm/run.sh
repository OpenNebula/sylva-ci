#!/usr/bin/env bash

set -eu -o pipefail

: "${SELF:=$(realpath $(dirname $0))}"
: "${CORE:=$(realpath $1)}"
: "${WORK:=$(mktemp -d /var/tmp/sylva-ci-XXXXX)}"

trap "rm --preserve-root -rf '$WORK'" ERR EXIT

tar --mode=u+rw,go+r -cf- -C "$CORE/" . | tar -xf- -C "$WORK/"

tar --mode=u+rw,go+r -cf- -C "$SELF/mgmt/" . | tar -xf- -C "$WORK/environment-values/"

tar --mode=u+rw,go+r -cf- -C "$SELF/wkld/" . | tar -xf- -C "$WORK/environment-values/workload-clusters/"

cd "$WORK/"

(./bootstrap.sh ./environment-values/my-kubeadm-capone)

(./apply-workload-cluster.sh ./environment-values/workload-clusters/my-kubeadm-capone)

(./apply.sh ./environment-values/my-kubeadm-capone)

(./apply-workload-cluster.sh ./environment-values/workload-clusters/my-kubeadm-capone)
