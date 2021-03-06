#!/bin/bash

# Copyright 2014 The Kubernetes Authors All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -o errexit
set -o nounset
set -o pipefail

sans=${1:-}
cert_dir=${CERT_DIR:-/srv/kubernetes}
cert_group=${CERT_GROUP:-kube-cert}

mkdir -p "$cert_dir"

use_cn=false

# TODO: Add support for discovery on other providers?
#if [ "$cert_ip" == "_use_gce_external_ip_" ]; then
#  cert_ip=$(curl -s -H Metadata-Flavor:Google http://metadata.google.internal./computeMetadata/v1/instance/network-interfaces/0/access-configs/0/external-ip)
#fi
#
#if [ "$cert_ip" == "_use_aws_external_ip_" ]; then
#  cert_ip=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)
#fi

tmpdir=$(mktemp -d -t kubernetes_cacert.XXXXXX)
trap 'rm -rf "${tmpdir}"' EXIT
cd "${tmpdir}"

# TODO: For now, this is a patched tool that makes subject-alt-name work, when
# the fix is upstream  move back to the upstream easyrsa.  This is cached in GCS
# but is originally taken from:
#   https://github.com/brendandburns/easy-rsa/archive/master.tar.gz
#
# To update, do the following:
# curl -o easy-rsa.tar.gz https://github.com/brendandburns/easy-rsa/archive/master.tar.gz
# gsutil cp easy-rsa.tar.gz gs://kubernetes-release/easy-rsa/easy-rsa.tar.gz
# gsutil acl ch -R -g all:R gs://kubernetes-release/easy-rsa/easy-rsa.tar.gz
#
# Due to GCS caching of public objects, it may take time for this to be widely
# distributed.
curl -L -O https://storage.googleapis.com/kubernetes-release/easy-rsa/easy-rsa.tar.gz > /dev/null 2>&1
tar xzf easy-rsa.tar.gz > /dev/null 2>&1

cd easy-rsa-master/easyrsa3
./easyrsa init-pki > /dev/null 2>&1
./easyrsa --batch "--req-cn=000@`date +%s`" build-ca nopass > /dev/null 2>&1
if [ $use_cn = "true" ]; then
    ./easyrsa build-server-full $cert_ip nopass > /dev/null 2>&1
    cp -p pki/issued/$cert_ip.crt "${cert_dir}/apiserver.pem" > /dev/null 2>&1
    cp -p pki/private/$cert_ip.key "${cert_dir}/apiserver-key.pem" > /dev/null 2>&1
else
    ./easyrsa --subject-alt-name="${sans}" build-server-full k8s-master nopass > /dev/null 2>&1
    cp -p pki/issued/k8s-master.crt "${cert_dir}/apiserver.pem" > /dev/null 2>&1
    cp -p pki/private/k8s-master.key "${cert_dir}/apiserver-key.pem" > /dev/null 2>&1
fi
./easyrsa build-client-full k8s-node nopass > /dev/null 2>&1
cp -p pki/ca.crt "${cert_dir}/ca.pem"
cp -p pki/issued/k8s-node.crt "${cert_dir}/node.pem"
cp -p pki/private/k8s-node.key "${cert_dir}/node-key.pem"

./easyrsa build-client-full nanokube-admin nopass > /dev/null 2>&1
cp -p pki/issued/nanokube-admin.crt "${cert_dir}/admin.pem"
cp -p pki/private/nanokube-admin.key "${cert_dir}/admin-key.pem"
# Make apiserver.pems accessible to apiserver.
chgrp $cert_group "${cert_dir}/apiserver-key.pem" "${cert_dir}/apiserver.pem" "${cert_dir}/ca.pem"
chmod 660 "${cert_dir}/apiserver-key.pem" "${cert_dir}/apiserver.pem" "${cert_dir}/ca.pem"
