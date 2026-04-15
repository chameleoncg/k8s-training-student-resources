# Pod Debugging

There are 8 deployments, each failing for a different reason. 

The goals:

* Determine the cause of the failure
* Identify a strategy to resolve the issue
* (Extra credit) Get the deployment working

To follow on lab by lab, deploy with:

```bash
make deploy-lab#
```

To clean up, run:

```bash
make clean-lab#
```

To deploy/clean up all, run:

```bash
make deploy-labs
make clean-labs
```

## Details

Look at each deployment, and investigate using using the debugging strategies discussed in training.

```bash
> kubectl get deployments -n debugging
```
