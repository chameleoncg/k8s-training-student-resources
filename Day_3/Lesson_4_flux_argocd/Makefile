setup: setup-cluster setup-flux

setup-cluster:
	@ registry_up
	@ kind_up

setup-kyverno: setup-cluster
	@ flux install

teardown:
	kind_down
	registry_down
