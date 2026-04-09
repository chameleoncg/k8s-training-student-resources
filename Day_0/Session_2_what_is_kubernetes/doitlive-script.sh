# This "script" is mean to be ran via doitlive (https://github.com/sloria/doitlive)

#doitlive speed: 1
#doitlive commentecho: true
#doitlive prompt: $
#doitlive alias: cat='batcat --paging=never'


#Docker is easy!
docker run hello-world

#
#Though you do need to remember some flags...
docker run --rm -it alpine sh -c "echo -e 'not so bad I guess...'"

#
#Let's run our website.
ls obscurity/

#
#Uh oh...this gets complicated.
docker run --rm --name obscurity-demo -e CREATED_VIA="Docker Run" -v $(pwd)/obscurity:/usr/share/caddy:ro -p 8080:80 caddy:alpine caddy file-server --root /usr/share/caddy --templates --access-log
clear

#
#Method: Docker Run
#
#docker run \
#  --rm \
#  --name obscurity-demo \
#  -e CREATED_VIA="Docker Run" \
#  -v $(pwd)/obscurity:/usr/share/caddy:ro \
#  -p 8080:80 \
#  caddy:alpine \
#  caddy file-server --root /usr/share/caddy --templates --access-log
#
#Q: Where is the complexity compared to other methods?
#Q: What would this be like to scale 100+ times?
#
clear


#Compose moves the complexity around.
cat compose.yaml

#
#Now that we've defined, declaration is simple.
docker compose -f compose.yaml up
docker compose -f compose.yaml down
clear

#
#Method: Docker Compose
#
#docker compose -f compose.yaml up
#
#Q: Where is the complexity compared to other methods?
#Q: What would this be like to scale 100+ times?
#
clear


#Kubernetes enables scale. Let's start with a local cluster.
cat kind-config.yaml
kind create cluster --name obscurity-cluster --config kind-config.yaml
clear

#The complexity of scale makes our definitions much larger...
cat manifest.yaml

#
#But now even declarations for highly scaled applications are made simple.
kubectl apply -f manifest.yaml
kubectl get pods -n obscurity-demo -w
#
kubectl logs -f obscurity-pod -n obscurity-demo
clear

#
#Method: Kubernetes Manifest
#
#kubectl apply -f manifest.yaml
#
#Q: Where is the complexity compared to other methods?
#Q: What would this be like to scale 100+ times?
#
clear


#End of demo!