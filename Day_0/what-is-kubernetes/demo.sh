# This "script" is mean to be ran via doitlive (https://github.com/sloria/doitlive)

#doitlive speed: 1
#doitlive commentecho: true
#doitlive prompt: $
#doitlive alias: cat=batcat

#
#1.1. Execution: Docker is easy!
docker run hello-world

#
#1.2. Execution: Though you do need to remember some flags...
docker run --rm -it alpine sh -c "echo -e 'not so bad I guess...'"

#
#1.3. Execution: Let's run our website. This gets complicated.
docker run --rm --name obscurity-demo -e CREATED_VIA="Docker Run" -v $(pwd)/obscurity:/usr/share/caddy:ro -p 8080:80 caddy:alpine caddy file-server --root /usr/share/caddy --templates --access-log

#
#2.1. Declaration: Compose makes the complexity easier.
cat compose.yaml

#
#2.2. Declaration: Now that we've declared, execution is simple.
docker compose up
docker compose down

#
#3.1. Scale: Now that we've declared, execution is simple.
