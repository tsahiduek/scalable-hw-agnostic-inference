https://awsdocs-neuron.readthedocs-hosted.com/en/latest/containers/kubernetes-getting-started.html#deploy-neuron-device-plugin

helm upgrade --install neuron-helm-chart oci://public.ecr.aws/neuron/neuron-helm-chart \
    --set "npd.enabled=false"

appsimulator service account - cloudwatch, SQS
https://github.com/yahavb/k8s-octo-pancake-config/blob/main/clusters/kub316/default/appsimulator-sa.yaml

kubectl apply -f appsimulator-sa.yaml
currently administrator access 

find-compute-breaking-point.yaml
before - deploy load deployment
https://github.com/yahavb/k8s-octo-pancake-config/tree/main/clusters/kub316/load
https://github.com/yahavb/k8s-octo-pancake-config/blob/main/clusters/kub316/load/load.yaml

capacity checker deploy can run on "regular" image