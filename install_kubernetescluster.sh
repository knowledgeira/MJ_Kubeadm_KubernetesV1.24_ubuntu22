#!/usr/bin/bash
BLUE='\033[0;34m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color
clear

if ! command -v mokutil &>/dev/null; then
    echo -e "Mokutil is not installed. Installing mokutil..."
    sudo apt update
    sudo apt install -y mokutil
fi

secure_boot_status=$(sudo mokutil --sb-state)
if [[ $secure_boot_status == "SecureBoot enabled" ]]; then
    echo -e "\n\nSTEP 1 :${GREEN}Secure boot: enabled . You need to disbale secure boot from bios\n\n.${NC}"
else
    echo -e "\n\nSTEP 1 :${GREEN}Secure boot: disabled.\n\n${NC}"
fi

if lscpu | grep -E 'CPU\(s\)|Thread|Core|Virtualization' &>/dev/null; then
    echo -e "\n\nSTEP 2 : ${BLUE}CPU, Thread, and Core information:${NC}"
    echo "------------------------------------------------"

    lscpu | grep -E 'CPU\(s\)|Thread|Core|Virtualization'
else
    echo -e "\n\nSTEP 2 : ${BLUE}Unable to get CPU, Thread, and Core information.${NC}"
    echo "------------------------------------------------"

fi

if lscpu | grep -i -E 'svm|vmx' &>/dev/null; then
    echo -e "\n\n${GREEN}STEP 3:Virtualization Status : It is enabled.${NC}"
    echo "------------------------------------------------"

else
    echo -e "\n\n${GREEN}STEP 3 :Virtualization Status: Not enabled.${NC}"
    echo "------------------------------------------------"

fi

if ! command -v vagrant &> /dev/null; then
    echo -e "\n\n ${BLUE}STEP 4 :Vagrant is not installed. Installing...${NC}"
    echo "------------------------------------------------"

    sudo apt update
    sudo apt install vagrant -y
else
    echo -e "\n\n${GREEN}STEP 4 :You already have Vagrant installed. Moving forward.${NC}"
    echo "------------------------------------------------"

fi

# Check if VirtualBox is installed
if ! command -v virtualbox &> /dev/null; then
    echo -e "\n\n${BLUE}STEP 5 :VirtualBox is not installed. Installing...${NC}"
    echo "------------------------------------------------"

    sudo apt update
    sudo apt install virtualbox -y
else
    echo -e "\n\n${GREEN}STEP 5 :You already have VirtualBox installed. Moving forward...${NC}"
    echo "------------------------------------------------"

fi

echo -e "Step 6: \n\n${BLUE}Deploying Kubernetes cluster${NC}"
echo "------------------------------------------------"
sleep 30
vagrant up
vagrant status

echo -e "Use vagrant ssh to k8sMaster and use below commands on master node for verification of Pods,Networkpolicies and Namespaces"
echo -e "kubectl get networkpolicies -n k8s-lab"
echo -e "kubectl get pods -n k8s-labs"
