Kubernetes
==========

A basic Helm chart is available for installing pgwatch2 to a Kubernetes cluster. The corresponding setup can be found in `pgwatch2-charts repository <https://github.com/cybertec-postgresql/pgwatch2-charts>`_, whereas installation is done via the following commands:

::

    cd openshift_k8s
    helm install -f chart-values.yml pgwatch2 ./helm-chart

Please have a look at `openshift_k8s/helm-chart/values.yaml <https://github.com/cybertec-postgresql/pgwatch2-charts/blob/main/helm/values.yaml>`_ to get additional information of configurable options.
