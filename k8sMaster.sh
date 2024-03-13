#!/bin/bash
#Author: Manoj Jagdale
set +x

echo "-------------------------------------------1.Installing Kublet,kubeadm,kubectl----------------------------------------------------------------------"

sudo apt-get update
sudo apt-get install -y apt-transport-https ca-certificates curl


curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.29/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.29/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list

sudo apt-get update
sudo apt install -y kubeadm=1.29.1-1.1 kubelet=1.29.1-1.1 kubectl=1.29.1-1.1
sudo apt-mark hold kubelet kubeadm kubectl


echo "-------------------------------------------2. Making Neccessary system Changes----------------------------------------------------------------------"

cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter

# sysctl params required by setup, params persist across reboots
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

# Apply sysctl params without reboot
#sudo sysctl --system
sudo systemctl restart systemd-sysctl



echo "Verifying Data"
lsmod | grep br_netfilter
lsmod | grep overlay
sysctl net.bridge.bridge-nf-call-iptables net.bridge.bridge-nf-call-ip6tables net.ipv4.ip_forward

echo "-------------------------------------------3. Installing Containerd.io and Docker ------------------------------------------------------------"



curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

echo  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
  
  
sudo apt-get update
sudo apt-get -y install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo swapoff -a
sudo sed -i 's|^/swap.img|#/swap.img|' /etc/fstab
sudo mkdir -p /etc/containerd
sudo containerd config default | sudo tee /etc/containerd/config.toml


sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
sudo systemctl restart containerd
sudo systemctl enable containerd
sudo apt-get -y install jq

sudo kubeadm config images pull --kubernetes-version 1.29.2
sudo kubeadm init --kubernetes-version=v1.29.2 --pod-network-cidr=10.244.0.0/16 --cri-socket=unix:///run/containerd/containerd.sock --apiserver-advertise-address 192.168.57.8
sudo kubeadm init --pod-network-cidr=10.244.0.0/16 --cri-socket unix:///run/containerd/containerd.sock --apiserver-advertise-address 192.168.57.8 --ignore-preflight-errors=all 

mkdir -p /home/vagrant/.kube
sudo mkdir -p /root/.kube
sudo chmod 777 /etc/kubernetes/admin.conf 

sudo cp  /etc/kubernetes/admin.conf /home/vagrant/.kube/config
sudo cp  /etc/kubernetes/admin.conf /root/.kube/config
#sudo chown $(id -u):$(id -g) $HOME/.kube/config
echo "Adding hostname and IP address mapping to /etc/hosts file..."
echo "192.168.57.8 k8sMaster" | sudo tee -a /etc/hosts > /dev/null
echo "192.168.57.9 k8sWorker1" | sudo tee -a /etc/hosts > /dev/null
echo "192.168.57.10 k8sWorker2" | sudo tee -a /etc/hosts > /dev/null
echo "Added master and worker hostname to IP mapping for DNS purposes."
master_ip=192.168.57.8
sha_token="$(openssl x509 -pubkey -in /etc/kubernetes/pki/ca.crt | openssl rsa -pubin -outform der 2>/dev/null | openssl dgst -sha256 -hex | sed 's/^.* //')"
token="$(kubeadm token list | awk '{print $1}' | sed -n '2 p')"

#echo "kubeadm join $master_ip:6443 --token=$token --discovery-token-ca-cert-hash sha256:$sha_token"
sudo wget https://github.com/containerd/nerdctl/releases/download/v0.19.0/nerdctl-0.19.0-linux-amd64.tar.gz
sudo tar Cxzvf /usr/local/bin nerdctl-0.19.0-linux-amd64.tar.gz

#sudo wget  https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml
sudo wget https://github.com/flannel-io/flannel/releases/download/v0.22.1/kube-flannel.yml
sudo sed -i '/- --kube-subnet-mgr/a\        - --iface=eth1' kube-flannel.yml
sudo kubectl apply -f kube-flannel.yml

#sudo kubectl taint nodes --all node-role.kubernetes.io/control-plane-

echo "sudo kubeadm join $master_ip:6443 --token=$token --discovery-token-ca-cert-hash sha256:$sha_token --ignore-preflight-errors=all" > join_command.txt


sudo sed -i "/^[^#]*PasswordAuthentication[[:space:]]no/c\PasswordAuthentication yes" /etc/ssh/sshd_config

#!/bin/bash
set -x

# Step 1: Create the k8s-lab namespace
kubectl create namespace k8s-lab || true  # Ensure the namespace exists

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

# Network policies for k8s-lab namespace
kubectl apply -n k8s-lab -f - <<EOF
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

echo "Pods and network policies created in namespace k8s-lab."



sudo systemctl restart sshd
