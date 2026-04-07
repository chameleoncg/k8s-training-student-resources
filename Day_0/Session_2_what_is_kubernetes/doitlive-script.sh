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
#
#Great! Now do that again 100 times...
clear


#Compose makes the complexity easier.
cat compose.yaml

#
#Now that we've declared, execution is simple.
docker compose up
docker compose down
#
#Great! Now do that again 100 times...
clear


#Let's start a local cluster
cat kind-config.yaml
kind create cluster --name obscurity-cluster --config kind-config.yaml
clear


#The complexity of scale makes our declarations much larger...
cat manifest.yaml

#
#But executing at scale is made simple.
kubectl apply -f manifest.yaml
kubectl get pods -n obscurity-demo -w
#
kubectl logs -f obscurity-pod -n obscurity-demo
clear


#End of demo!