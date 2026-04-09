# What is Kubernetes? It’s All Greek to Me
This is the code for running the demo section of this Day 0 brownbag.

## Our Example
Let’s run a website! We sell tshirts.

We’ll run our containerized application using three methods:
* Docker via command line
* Docker via Compose
* Kubernetes via manifest

At each stage, let’s ask ourselves these questions:
* Where is the complexity compared to other methods?
* What would this be like to scale 100+ times?

## Quickstart
```
./run-demo.sh
```
Requires: `Docker`, `Compose`, `KIND`, `kubectl`, `doitlive`, `batcat`