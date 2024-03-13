it creates the k8-lab namespace, deploys a set of pods each with specific labels (and in the case of the mariadb-pod, an environment variable), and applies a series of network policies that dictate the allowed traffic flows between these pods.

#!/bin/bash
set -x

# Step 1: Create the k8-lab namespace
kubectl create namespace k8-lab || true  # Ensure the namespace exists

# Function to create a Pod within k8-lab namespace with the given name, image, labels, and optional environment variables
create_pod() {
  local pod_name=$1
  local image=$2
  local labels=$3
  local env_var_name=$4
  local env_var_value=$5

  # Construct the labels YAML
  local yaml_labels=""
  IFS=',' read -ra LABEL_PAIRS <<< "$labels"
  for pair in "${LABEL_PAIRS[@]}"; do
    IFS='=' read -r key value <<< "$pair"
    yaml_labels="${yaml_labels}    ${key}: ${value}\n"
  done

  # Construct the environment variables YAML, if provided
  local yaml_env_vars=""
  if [[ -n "$env_var_name" ]] && [[ -n "$env_var_value" ]]; then
    yaml_env_vars="    env:\n    - name: ${env_var_name}\n      value: \"${env_var_value}\""
  fi

  # Check if it's a busybox pod to apply a different command
  local pod_command=""
  if [[ "$pod_name" == "busybox-pod" ]]; then
    pod_command="    command: [\"tail\", \"-f\", \"/dev/null\"]"
  fi

  # Apply the pod configuration within the k8-lab namespace
  cat <<EOF | kubectl apply -n k8-lab -f -
apiVersion: v1
kind: Pod
metadata:
  name: $pod_name
  labels:
$(echo -e "$yaml_labels")
spec:
  containers:
  - name: ${pod_name}-container
    image: $image
$(echo -e "$yaml_env_vars")
$(echo -e "$pod_command")
EOF
}

# Pod definitions (original setup retained)
LABELS_MARIADB="app=mariadb,env=dev"
LABELS_TOMCAT="app=tomcat,env=prod"
LABELS_APACHE="app=apache,env=prod"
LABELS_NGINX="app=nginx,env=dev"
LABELS_MONGODB="app=mongodb,env=prod"
LABELS_BUSYBOX="app=busybox"

create_pod mariadb-pod "mariadb:latest" "$LABELS_MARIADB" "MARIADB_ROOT_PASSWORD" "mysecretpassword"
create_pod tomcat-pod "tomcat:latest" "$LABELS_TOMCAT"
create_pod apache-pod "httpd:latest" "$LABELS_APACHE"
create_pod nginx-pod "nginx:latest" "$LABELS_NGINX"
create_pod mongodb-pod "mongo:latest" "$LABELS_MONGODB"
create_pod busybox-pod "busybox:latest" "$LABELS_BUSYBOX"

# Network policies for k8-lab namespace
kubectl apply -n k8-lab -f - <<EOF
# Allow all ingress traffic within the namespace
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-all-internal
spec:
  podSelector: {}
  ingress:
    - from:
      - podSelector: {}
---
# Allow traffic from env=dev to env=prod
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-dev-to-prod
spec:
  podSelector:
    matchLabels:
      env: prod
  ingress:
  - from:
    - podSelector:
        matchLabels:
          env: dev
---
# Deny traffic from app=busybox to all other pods
# (Since Kubernetes network policies are allow-only, this policy ensures
#  that no pods allow ingress from app=busybox by not specifying it.)
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-from-busybox
spec:
  podSelector: {}  # Apply to all pods
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchExpressions:
          - {key: app, operator: NotIn, values: [busybox]}
---
# Allow traffic to app=mariadb only from pods with app=nginx
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-nginx-to-mariadb
spec:
  podSelector:
    matchLabels:
      app: mariadb
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: nginx
EOF

# Additional network policies can be defined following the same pattern

echo "Pods and network policies created in namespace k8-lab."
