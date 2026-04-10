Copy and paste from here to make your lab experience better

# Required applications

* oras [https://github.com/oras-project/oras/releases/tag/v1.3.1](https://github.com/oras-project/oras/releases/tag/v1.3.1)   
* tree

# OCI Setup

Bring up the registry

```shell
registry_up
```

Ensure nginx is in the registry

```shell
oras copy docker.io/library/nginx@sha256:7150b3a39203cb5bee612ff4a9d18774f8c7caf6399d6e8985e97e28eb751c18 --to-plain-http lab.registry:5050/nginx:whatever-02
```

# Behold your OCI registry

```shell
ls ~/.registry/data/docker/registry/v2
```

Here’s everything that makes up “nginx”

```shell
tree ~/.registry/data/docker/registry/v2/repositories/nginx/
```

Note these link files \- let’s take a look

```shell
cat ~/.registry/data/docker/registry/v2/repositories/nginx/_manifests/tags/whatever-02/index/sha256/7150b3a39203cb5bee612ff4a9d18774f8c7caf6399d6e8985e97e28eb751c18/link
```

This is just a text file repeating the sha256sum. If we really want to see the files, we have to go the the blobs dir.


```shell
cat ~/.registry/data/docker/registry/v2/blobs/sha256/71/7150b3a39203cb5bee612ff4a9d18774f8c7caf6399d6e8985e97e28eb751c18/data | jq '.manifests |= map(select(.platform.architecture | startswith("a") and endswith("64")))'
```

# Look, it’s the same

Let’s use this same shasum from before to pull the same manifest, but from docker (I also highly recommend that same jq filter):

```shell
oras manifest fetch docker.io/library/nginx@sha256:7150b3a39203cb5bee612ff4a9d18774f8c7caf6399d6e8985e97e28eb751c18 | jq '.manifests |= map(select(.platform.architecture | startswith("a") and endswith("64")))'
```

Look closely at the `amd64` section; see that digest and mediatype? That’s pointing us to the blob holding the manifest for `amd64` containers. Let’s pull it. And since we copied all of this container image’s layers down already, let’s query our local registry for it:

```shell
oras manifest fetch lab.registry:5050/nginx@sha256:c3fe1eeae810f4a585961f17339c93f0fb1c7c8d5c02c9181814f52bdd51961c --plain-http | jq
```

See up top, that familiar digest under config? Let’s pull that \- you choose; docker or local; NOTE slightly different command since this isn’t a manifest technically, its a config

```shell
oras blob fetch docker.io/library/nginx@sha256:0cf1d6af5ca72e2ca196afdbdbe26d96f141bd3dc14d70210707cf89032ea217 --output - | jq
```

OR

```shell
oras blob fetch lab.registry:5050/nginx@sha256:0cf1d6af5ca72e2ca196afdbdbe26d96f141bd3dc14d70210707cf89032ea217 --plain-http --output - | jq
```

OR

```shell
cat ~/.registry/data/docker/registry/v2/blobs/sha256/0c/0cf1d6af5ca72e2ca196afdbdbe26d96f141bd3dc14d70210707cf89032ea217/data  | jq
```

And here’s a diff command if you trust me, but want to verify for yourself that these are all the same

```shell
diff3 \
<(oras blob fetch docker.io/library/nginx@sha256:0cf1d6af5ca72e2ca196afdbdbe26d96f141bd3dc14d70210707cf89032ea217 --output -) \
<(oras blob fetch lab.registry:5050/nginx@sha256:0cf1d6af5ca72e2ca196afdbdbe26d96f141bd3dc14d70210707cf89032ea217 --plain-http --output -) \
~/.registry/data/docker/registry/v2/blobs/sha256/0c/0cf1d6af5ca72e2ca196afdbdbe26d96f141bd3dc14d70210707cf89032ea217/data
```

# If this is all standard, why stop at containers?

Let’s look at the prometheus helm chart \- note that we’re using identical commands as before and irreverently switching between the remote and local repositories.

```shell
oras copy ghcr.io/prometheus-community/charts/prometheus@sha256:fce3103ca5b17f921901752bad8933641e7a240a6fd209a8609f2be749825844 --to-plain-http lab.registry:5050/prometheus:whatever-02
```

```shell
oras manifest fetch lab.registry:5050/prometheus@sha256:fce3103ca5b17f921901752bad8933641e7a240a6fd209a8609f2be749825844 --plain-http| jq
```

Look\! A config, lets check it out

```shell
oras blob fetch ghcr.io/prometheus-community/charts/prometheus@sha256:f60400124657ed8d6e81896380c22da05830d47d873bfd55de822edf2bb4b87f --output - | jq
```

Anything stand out to you here?

Ok let’s go back and see what’s in the layer with the tar+gzip mediaType \- I bet that’s a helm chart

```shell
oras blob fetch lab.registry:5050/prometheus@sha256:f6d3e02c15bb4df2f01bb58d56cd61f2d2a05701f111c9bffcd409140fd738e5 --plain-http --output - | tar -zt
```

Hmm, let’s look at the chart metadata \- just to prove this is actually a helm chart

```shell
oras blob fetch ghcr.io/prometheus-community/charts/prometheus@sha256:f6d3e02c15bb4df2f01bb58d56cd61f2d2a05701f111c9bffcd409140fd738e5 --output - | tar -zxO prometheus/Chart.yaml
```

How does this compare to that config we saw before?

# A Sane API Standard

Grab an OAuth2 token:

```shell
TOKEN=$(curl -s "https://ghcr.io/token?scope=repository:prometheus-community/charts/prometheus:pull" | jq -r '.token')
```

Then we can just pull it:

```shell
curl -Ls -H "Authorization: Bearer $TOKEN" "https://ghcr.io/v2/prometheus-community/charts/prometheus/blobs/sha256:f6d3e02c15bb4df2f01bb58d56cd61f2d2a05701f111c9bffcd409140fd738e5" | tar -zxO prometheus/Chart.yaml
```

# I WANT MY OWN

Ok ok ok, here’s how you can push your very own OCI artifact to your local registry

Let’s build out the payload

```shell
mkdir -p ~/bundle
echo "deny-all-ingress: true" > ~/bundle/network-policy.yaml
echo "environment: obscurity" > ~/bundle/config.json
# put whatever else you want in the ~/bundle dir
```

Now let’s push it

```shell
cd ~/
oras push --plain-http lab.registry:5050/obscurity/config-bundle:cool.beans ./bundle/:application/vnd.acme.config.v1+gzip
```

# Validating our Push

Let’s take a look in the registry:

```shell
tree ~/.registry/data/docker/registry/v2/repositories/obscurity/
```

Let’s check out the manifest to see what we’re dealing with there \- using tags because idk what you put in your bundle files

```shell
oras manifest fetch --plain-http lab.registry:5050/obscurity/config-bundle:cool.beans | jq

```

Let’s take a look at that layer (the only one)

Let’s grab the digest first (idk what you did with your bundle!)

```shell
COOL_DIGEST=$(oras manifest fetch --plain-http lab.registry:5050/obscurity/config-bundle:cool.beans | jq -r '.layers[0].digest')
```

```shell
cat ~/.registry/data/docker/registry/v2/blobs/sha256/${COOL_DIGEST:7:2}/${COOL_DIGEST:7}/data | tar -ztO
```

Ok let’s look at the config.json file

```shell
cat ~/.registry/data/docker/registry/v2/blobs/sha256/${COOL_DIGEST:7:2}/${COOL_DIGEST:7}/data | tar -zxO bundle/config.json
```

# Referrers API

Ok let’s imagine that we submitted it to ourselves for approval and we signed off?

COOL BEANS has been approved, let’s sign it\!

```shell
cd ~/
echo "approved by ourselves" > ./signature.txt
oras attach --plain-http lab.registry:5050/obscurity/config-bundle:cool.beans \
    --artifact-type application/vnd.example.signature.v1 \
    signature.txt
```

Wanna see the signature?

```shell
oras discover --plain-http lab.registry:5050/obscurity/config-bundle:cool.beans
```

Of course this isn’t actually cryptographically signed, but it’s attached to the oci artifact without making us change the artifact itself. FYSA, this functionality is pretty new, so it might not be in effect everywhere.

Also noting that the signature does NOT appear as a tag

```shell
tree ~/.registry/data/docker/registry/v2/repositories/obscurity/
```

# Revisiting Tags

Wanna know what really happens when you add a tag to an image?

```shell
oras tag lab.registry:5050/obscurity/config-bundle:cool.beans da-bes --plain-http

tree ~/.registry/data/docker/registry/v2/repositories/obscurity/
```

cool.beans and da-bes both point to the same thing\! 

But remember anyone with privs can update any tag to say anything The digest is the only truth. If we really want to hit what we pushed, we need to use the sha.

```shell
TheOneTrueDigest=$(oras resolve lab.registry:5050/obscurity/config-bundle:cool.beans --plain-http)

oras manifest fetch lab.registry:5050/obscurity/config-bundle@$TheOneTrueDigest --plain-http |jq
```

Let me foot stomp:

If it’s in Production, it **must** be referenced by Digest.  
Digests are the only way you can be **sure** you are pulling the expected image.

*While developing this training, I used a tag to pull from docker, then good-friend Fili ran through it and the shasums didn’t work.*

# Troubleshooting

## Can’t pull an image for some reason? Oras `-d` for debug.

```shell
oras manifest fetch -d lab.registry:5050/nginx:not-here --plain-http
```

## Need to find something? try introspecting the registry

```shell
oras repo ls lab.registry:5050 --plain-http

oras repo tags lab.registry:5050/nginx --plain-http
```

## `ImagePullBackOff` or `ErrImagePull` but you know the image exists?

Are you on an *alternate* architecture, ahem (M-series mac users stand up). Use the jq filter we used before to check if your architecture event exists in the image index

```shell
oras manifest fetch lab.registry:5050/nginx@sha256:7150b3a39203cb5bee612ff4a9d18774f8c7caf6399d6e8985e97e28eb751c18 --plain-http | jq '.manifests |= map(select(.platform.architecture | startswith("a") and endswith("64")))'
```

## `helm Install` not working?

There’s a chance someone pushed with `oras push`, but neglected to set the correct `mediaType`. We touched on those earlier \- those are serious business and clients behave differently based on those. 

For helm, it’s `application/vnd.cncf.helm.chart.content.v1.tar+gzip` or go home.

# Cleanup

```shell
rm -r ~/bundle signature.txt
unset -v TOKEN COOL_DIGEST TheOneTrueDigest
```

