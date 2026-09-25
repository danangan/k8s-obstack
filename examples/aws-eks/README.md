# Deployment to AWS EKS example

Deploys the stack and the [sample app](../../local-dev/sample-app/) to an existing EKS cluster.

Set the cluster name and region at the top of [deploy.sh](deploy.sh), then run it. It connects
kubectl to the cluster with `aws eks update-kubeconfig` and deploys the chart with
[values.yaml](values.yaml): small sizes for testing, on any node instead of a dedicated node group.
The cluster needs the AWS Load Balancer Controller and the EBS CSI driver (see the
[prerequisites](../../README.md#prerequisites)).

From the repository root:

```sh
# 1. Deploy the stack
./examples/aws-eks/deploy.sh

# 2. Build the sample app for arm64, push it to ECR (repository `sample-app`) and deploy it
./examples/aws-eks/deploy-sample-app.sh

# 3. Forward a local port to the sample app (leave this running)
kubectl port-forward svc/sample-app 8000:80

# 4. Generate some traffic
for i in $(seq 20); do curl -s -XPOST "http://localhost:8000/orders?item=book&quantity=2"; echo; done
```

Then open Grafana as described in [Explore in Grafana](../../README.md#3-explore-in-grafana).

## Clean up

Do this before deleting the cluster. The cluster's controllers created the load balancer and the
volumes, so deleting the cluster alone leaves them behind, and the load balancer then blocks
deleting the VPC.

```sh
# Removes Grafana's Ingress, and with it the load balancer
helm uninstall sample-app
helm uninstall obstack
kubectl delete namespace obstack

# The StorageClass keeps the volumes (reclaim policy Retain): delete them, and the ECR repository
for v in $(aws ec2 describe-volumes --region us-east-1 --query 'Volumes[].VolumeId' --output text \
    --filters Name=tag:kubernetes.io/created-for/pvc/namespace,Values=obstack); do
  aws ec2 delete-volume --region us-east-1 --volume-id "$v"
done
aws ecr delete-repository --region us-east-1 --repository-name sample-app --force
```
