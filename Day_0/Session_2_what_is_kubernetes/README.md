# What is Kubernetes? It’s All Greek to Me
This is the code for running the demo section of this Day 0 brownbag.

## Our Example
Let’s run a website! We sell tshirts.

We’ll run our containerized application using three methods:
1. Docker via command line
2. Docker via Compose
3. Kubernetes via manifest

At each stage, let’s ask ourselves these questions:
* Where is the complexity compared to other methods?
* What would this be like to scale 100+ times?
* How does networking work?

## Quickstart
```
./run-demo.sh
```
Requires: `Docker`, `Compose`, `KIND`, `kubectl`, `doitlive`