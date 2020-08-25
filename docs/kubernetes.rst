Kubernetes
==========

A basic Helm chart is available for installing pgwatch2 to a Kubernetes cluster. The corresponding setup can be found in `./openshift_k8s/helm-chart`, whereas installation is done via the following commands:

::

    cd openshift_k8s
    helm install ./helm-chart --name pgwatch2 -f chart-values.yml

Please have a look at `openshift_k8s/helm-chart/values.yaml` to get additional information of configurable options.
