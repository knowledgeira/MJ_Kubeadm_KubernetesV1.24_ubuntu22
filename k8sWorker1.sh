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



echo "-------------------------------------------2. Starting In system Changes----------------------------------------------------------------------"

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
sudo wget https://github.com/containerd/nerdctl/releases/download/v0.19.0/nerdctl-0.19.0-linux-amd64.tar.gz
sudo tar Cxzvf /usr/local/bin nerdctl-0.19.0-linux-amd64.tar.gz

echo "Adding hostname and IP address mapping to /etc/hosts file..."
echo "192.168.57.8 k8sMaster" | sudo tee -a /etc/hosts > /dev/null
echo "192.168.57.9 k8sWorker1" | sudo tee -a /etc/hosts > /dev/null
echo "192.168.57.10 k8sWorker2" | sudo tee -a /etc/hosts > /dev/null
echo "Added master and worker hostname to IP mapping for DNS purposes."

sudo apt-get install sshpass
sudo sshpass -pvagrant scp -o StrictHostKeyChecking=no vagrant@192.168.57.8:/home/vagrant/join_command.txt .
sudo bash join_command.txt
