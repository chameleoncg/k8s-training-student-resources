# This "script" is meant to be ran via doitlive (https://github.com/sloria/doitlive)

#doitlive speed: 4
#doitlive commentecho: false
#doitlive prompt: $

# Bring up the registry
registry_up

# Ensure nginx is in the registry
oras copy docker.io/library/nginx@sha256:7150b3a39203cb5bee612ff4a9d18774f8c7caf6399d6e8985e97e28eb751c18 --to-plain-http lab.registry:5050/nginx:whatever-02

# The registry!1!!11
ls ~/.registry/data/docker/registry/v2

# Here’s everything that makes up “nginx”
tree ~/.registry/data/docker/registry/v2/repositories/nginx/

# Let’s look at those link files
cat ~/.registry/data/docker/registry/v2/repositories/nginx/_manifests/tags/whatever-02/index/sha256/7150b3a39203cb5bee612ff4a9d18774f8c7caf6399d6e8985e97e28eb751c18/link

# If we really want to see the files, we must...
cat ~/.registry/data/docker/registry/v2/blobs/sha256/71/7150b3a39203cb5bee612ff4a9d18774f8c7caf6399d6e8985e97e28eb751c18/data | jq '.manifests |= map(select(.platform.architecture | startswith("a") and endswith("64")))'

# Using the same shasum from before to pull the same manifest from docker
oras manifest fetch docker.io/library/nginx@sha256:7150b3a39203cb5bee612ff4a9d18774f8c7caf6399d6e8985e97e28eb751c18 | jq '.manifests |= map(select(.platform.architecture | startswith("a") and endswith("64")))'

# Let’s pull the amd64 manifest
oras manifest fetch lab.registry:5050/nginx@sha256:c3fe1eeae810f4a585961f17339c93f0fb1c7c8d5c02c9181814f52bdd51961c --plain-http | jq

# Let’s pull the config digest; I’ll pull from docker, YOU chose your own adventure
oras blob fetch docker.io/library/nginx@sha256:0cf1d6af5ca72e2ca196afdbdbe26d96f141bd3dc14d70210707cf89032ea217 --output - | jq

# A diff command... hopefully it’s blank
diff3 <(oras blob fetch docker.io/library/nginx@sha256:0cf1d6af5ca72e2ca196afdbdbe26d96f141bd3dc14d70210707cf89032ea217 --output -) <(oras blob fetch lab.registry:5050/nginx@sha256:0cf1d6af5ca72e2ca196afdbdbe26d96f141bd3dc14d70210707cf89032ea217 --plain-http --output -) ~/.registry/data/docker/registry/v2/blobs/sha256/0c/0cf1d6af5ca72e2ca196afdbdbe26d96f141bd3dc14d70210707cf89032ea217/data

# Ensure we have the prometheus helm chart locally
oras copy ghcr.io/prometheus-community/charts/prometheus@sha256:fce3103ca5b17f921901752bad8933641e7a240a6fd209a8609f2be749825844 --to-plain-http lab.registry:5050/prometheus:whatever-02

# Peering upon the prometheus helm chart
oras manifest fetch lab.registry:5050/prometheus@sha256:fce3103ca5b17f921901752bad8933641e7a240a6fd209a8609f2be749825844 --plain-http| jq

# A config! Lets check it out...
oras blob fetch ghcr.io/prometheus-community/charts/prometheus@sha256:f60400124657ed8d6e81896380c22da05830d47d873bfd55de822edf2bb4b87f --output - | jq

# Let’s go back and see what’s in tar+gzip mediaType layer... smells helmish
oras blob fetch lab.registry:5050/prometheus@sha256:f6d3e02c15bb4df2f01bb58d56cd61f2d2a05701f111c9bffcd409140fd738e5 --plain-http --output - | tar -zt

# Let’s look at the chart metadata...
oras blob fetch ghcr.io/prometheus-community/charts/prometheus@sha256:f6d3e02c15bb4df2f01bb58d56cd61f2d2a05701f111c9bffcd409140fd738e5 --output - | tar -zxO prometheus/Chart.yaml

# CURL IS ALL WE NEED
# Grab an OAuth2 token:
#doitlive commentecho: true
#doitlive env: TOKEN=$(curl -s "https://ghcr.io/token?scope=repository:prometheus-community/charts/prometheus:pull" | jq -r '.token')
#TOKEN=$(curl -s "https://ghcr.io/token?scope=repository:prometheus-community/charts/prometheus:pull" | jq -r '.token')
#doitlive commentecho: false

# Then we can pull the chart:
curl -Ls -H "Authorization: Bearer $TOKEN" "https://ghcr.io/v2/prometheus-community/charts/prometheus/blobs/sha256:f6d3e02c15bb4df2f01bb58d56cd61f2d2a05701f111c9bffcd409140fd738e5" | tar -zxO prometheus/Chart.yaml

# Let’s build our own OCI artifact
mkdir -p ~/bundle
echo "deny-all-ingress: true" > ~/bundle/network-policy.yaml
echo "environment: obscurity" > ~/bundle/config.json
# put whatever else you want in the ~/bundle dir

# Pushing the artifact
cd ~/
oras push --plain-http lab.registry:5050/obscurity/config-bundle:cool.beans ./bundle/:application/vnd.acme.config.v1+gzip

# Looking in the registry
tree ~/.registry/data/docker/registry/v2/repositories/obscurity/

# manifest introspection
oras manifest fetch --plain-http lab.registry:5050/obscurity/config-bundle:cool.beans | jq

# Grabbing the digest for the first layer
#doitlive commentecho: true
#doitlive env: COOL_DIGEST=$(oras manifest fetch --plain-http lab.registry:5050/obscurity/config-bundle:cool.beans | jq -r '.layers[0].digest')
#COOL_DIGEST=$(oras manifest fetch --plain-http lab.registry:5050/obscurity/config-bundle:cool.beans | jq -r '.layers[0].digest')
#doitlive commentecho: false

# Listing the contents of the first layer
cat ~/.registry/data/docker/registry/v2/blobs/sha256/${COOL_DIGEST:7:2}/${COOL_DIGEST:7}/data | tar -ztO

# Looking at config.json
cat ~/.registry/data/docker/registry/v2/blobs/sha256/${COOL_DIGEST:7:2}/${COOL_DIGEST:7}/data | tar -zxO bundle/config.json

# Signing cool beans
cd ~/
echo "approved by ourselves" > ./signature.txt
oras attach --plain-http lab.registry:5050/obscurity/config-bundle:cool.beans --artifact-type application/vnd.example.signature.v1 signature.txt

# The signature
oras discover --plain-http lab.registry:5050/obscurity/config-bundle:cool.beans

# The signature is not a tag
tree ~/.registry/data/docker/registry/v2/repositories/obscurity/

# new tag time
oras tag lab.registry:5050/obscurity/config-bundle:cool.beans da-bes --plain-http
tree ~/.registry/data/docker/registry/v2/repositories/obscurity/

# The digest is the only truth.
#doitlive commentecho: true
#doitlive env: TheOneTrueDigest=$(oras resolve lab.registry:5050/obscurity/config-bundle:cool.beans --plain-http)
#TheOneTrueDigest=$(oras resolve lab.registry:5050/obscurity/config-bundle:cool.beans --plain-http)
#doitlive commentecho: false
oras manifest fetch lab.registry:5050/obscurity/config-bundle@$TheOneTrueDigest --plain-http |jq

# Oras -d for debug
oras manifest fetch -d lab.registry:5050/nginx:not-here --plain-http

# Registry introspection
oras repo ls lab.registry:5050 --plain-http
oras repo tags lab.registry:5050/nginx --plain-http

# Errors but you know the image exists?
oras manifest fetch lab.registry:5050/nginx@sha256:7150b3a39203cb5bee612ff4a9d18774f8c7caf6399d6e8985e97e28eb751c18 --plain-http | jq '.manifests |= map(select(.platform.architecture | startswith("a") and endswith("64")))'

# Cleanup
rm -r ~/bundle signature.txt
#doitlive commentecho: true
#unset -v TOKEN COOL_DIGEST TheOneTrueDigest
#doitlive unset TOKEN COOL_DIGEST TheOneTrueDigest
#doitlive commentecho: false
