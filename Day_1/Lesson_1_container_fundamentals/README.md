# Container Fundamental Labs
## LAB 1 - The "hello world" container
1. Run `docker pull nginx@sha256:7150b3a39203cb5bee612ff4a9d18774f8c7caf6399d6e8985e97e28eb751c18 && docker tag nginx@sha256:7150b3a39203cb5bee612ff4a9d18774f8c7caf6399d6e8985e97e28eb751c18 nginx:latest` to pull the nginx image.
2. Start a nginx instance. `docker run --name=helloworld -d --rm -p 127.0.0.1:8080:80 -v $(pwd)/files/:/usr/share/nginx/html:ro nginx:latest`
3. Lets curl our webapp `curl 127.0.0.1:8080`

## LAB 2 - The “hello world” Container - Digging Deeper
1. Look at running containers with docker `docker container ls`
2. Inspect the helloworld container with docker `docker container inspect helloworld`
3. Look at running containers with containerd's cli `sudo ctr  --namespace moby container list`
4. Inspect the helloworld container with ctr `sudo ctr  --namespace moby container info f78c9122a1017399c796f36dfb6cde833eea53543c58b8a90347dccab549776c`
5. Look at running containers with runc `sudo runc --root /run/docker/runtime-runc/moby list`
6. inspect the helloworld container with runc `sudo runc --root /run/docker/runtime-runc/moby state f78c9122a1017399c796f36dfb6cde833eea53543c58b8a90347dccab549776c`

## LAB 3 - The “hello world” Container - Digging Deeperer
1. Inspect the helloworld container with runc `sudo runc --root /run/docker/runtime-runc/moby state f78c9122a1017399c796f36dfb6cde833eea53543c58b8a90347dccab549776c` and note the pid
2. Inspect the helloworld nginx process with ps `ps -fp <pid>`
3. List the namespaces associated with the helloworld container with lsns `sudo lsns -p <pid>`
4. Look at the root file system of the host with ls `ls -la /`
5. Look at the root file system of helloworld with nsenter `sudo nsenter -t 1829878 –root ls -la /`
6. Open a shell in the container using nsenter `sudo nsenter -t 1829878 --root --mount --pid --ipc --uts --net --time --cgroup  -- /bin/bash -l`
7. Type `exit` and open a shell with docker's cli `docker exec -it helloworld /bin/bash`

## LAB 4 - The “hello world” Container - Digging Deepererer
1. Download the nginx image and untar it. `mkdir -p nginx && docker save nginx:latest -o nginx.tar && tar -xf nginx.tar -C nginx`
2. Use ls to look at the contents of the nginx image `ls nginx` then `ls nginx/blobs/sha256/`
3. Inspect the manifest.json `jq . nginx/manifest.json`
4. Get the blob containing the image config `jq .[0].Config nginx/manifest.json`
5. Now look at the image config `jq . nginx/blobs/sha256/0cf1d6af5ca72e2ca196afdbdbe26d96f141bd3dc14d70210707cf89032ea217`
6. Lets untar one of the image layers. `mkdir -p nginx/blob_contents && tar -xf nginx/blobs/sha256/188c9b34dfbe022075d01fc4f5a305412909ef97de440783c15043e68e1b1913 -C nginx/blob_contents`
7. Look at the contents of the layer. `ls -la nginx/blob_contents`

## LAB 5 - The “hello world” Container - Digging Deeperererer
1. Look at the graphdriver of the helloworld container. `docker container inspect helloworld | jq '.[0].GraphDriver'`
2. Check out the root mount for the helloworld container. `sudo ls /var/lib/docker/overlay2/<layer id for step 1>/`
3. Look at the diff directory `sudo ls /var/lib/docker/overlay2/<layer id for step 1>/diff/`
4. Exec into the helloworld container with `docker exec -it helloworld /bin/bash -c “echo "Just leaving my mark" > note.txt; ls .”`
5. Look at the diff directory again `sudo ls /var/lib/docker/overlay2/<layer id for step 1>/diff/`
6. Look at two lowerdir layers `sudo ls /var/lib/docker/overlay2/c2c5f5fc302d26521909ee3ac5f35a6138c799ad5976815c2fdcb729dc4051c5/diff/docker-entrypoint.d/` and then `sudo ls /var/lib/docker/overlay2/c8d193c38bd164c1bb354772f1c64d35d462e614fcf63d00b9c01754a7112890/diff/docker-entrypoint.d/15-local-resolvers.envsh`
7. Check out the [nginx Dockerfile](https://github.com/nginx/docker-nginx/blob/master/Dockerfile-debian.template#L129) and see that those layers come from the docker build itself.