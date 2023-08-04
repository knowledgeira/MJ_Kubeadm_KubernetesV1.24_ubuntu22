#!/bin/bash
#Author: Manoj Jagdale
set +x

echo "-------------------------------------------1.Installing Kublet,kubeadm,kubectl----------------------------------------------------------------------"
   # Update the apt package index and install packages needed to use the Kubernetes apt repository:

sudo apt-get update
sudo apt-get install -y apt-transport-https ca-certificates curl

    #Download the Google Cloud public signing key:
sudo mkdir /etc/apt/keyrings
sudo curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -


#Add the Kubernetes apt repository:

echo "deb https://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee /etc/apt/sources.list.d/kubernetes.list

sudo apt-get update
sudo apt install -y kubelet=1.27.3-00 kubeadm=1.27.3-00 kubectl=1.27.3-00
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
sudo sysctl --system

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

sudo kubeadm config images pull --kubernetes-version 1.27.3
sudo kubeadm init --kubernetes-version=v1.27.3 --pod-network-cidr=10.244.0.0/16 --cri-socket=unix:///run/containerd/containerd.sock --apiserver-advertise-address 192.168.57.8
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
sudo systemctl restart sshd
