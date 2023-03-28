#!/bin/bash

# exit when any command fails
#set -e
# activate script debug mode
#set -x

#@file
# KUBERNETES Master / Worker node setup process automation
#
# NOTE ! This script expects to be running as under ROOT ID
#
# Sources
# - https://kubernetes.io/docs/setup/production-environment/
# - https://computingforgeeks.com/deploy-kubernetes-cluster-on-ubuntu-with-kubeadm/
# - https://karneliuk.com/2022/09/kubernetes-001-building-cluster-on-ubuntu-linux-with-docker-and-calico-in-2022/

###
### GLOBALS
###
DEBUG_ON=0
K8S_NODE_TYPE="None"
K8S_LOG_FILE="/var/log/k8s-install.log"
K8S_CORE="kubernetes-1.26.2"
K8S_REPO_KEY="https://packages.cloud.google.com/apt/doc/apt-key.gpg"
K8S_APT_DIST="kubernetes-xenial"
K8S_USER="k8s-master"
K8S_GROUP="kubernetes"
K8S_INSTALL_DIR="/opt/k8s-node"
K8S_POD_NET="10.66.0.0/16"
DOCKER_APT_KEY="https://download.docker.com/linux/ubuntu/gpg"

###
### Logging levels 
###
function error() { echo -e "[\e[31m  ERROR  \e[0m]-$(date --rfc-3339=seconds)-$1" | tee -a ${K8S_LOGFILE}; }
function warn()  { echo -e "[\e[33m WARNING \e[0m]-$(date --rfc-3339=seconds)-$1" | tee -a ${K8S_LOGFILE}; }
function info()  { echo -e "[\e[32m  INFOS  \e[0m]-$(date --rfc-3339=seconds)-$1" | tee -a ${K8S_LOGFILE}; }
function blog()  { echo -e " $1" | tee -a ${K8S_LOGFILE}; }

###
### Log header
###
function log_header()
{
    blog "*************************************************************"
    blog "** K8S ${K8S_NODE_TYPE} Node - Unattended installation "
    blog "** Date: $(date -R)"
    blog "** Started: $0 $*"
    blog ""
}

#
# Log footer.
#
function log_footer()
{
    blog "**************************************************************"
    blog "** Date: $(date -R)"
    blog "** End Of File"
    blog "**************************************************************"
}

###
### Debug Mode
###
function debug_mode()
{
    if [[ ${DEBUG_ON} -eq 1 ]]; then
        info "DEBUG - User Information"
        id | tee -a ${K8S_LOGFILE};
        info "DEBUG - Process Information"
        ps waux | tee -a ${K8S_LOGFILE};
        info "DEBUG - Network Information"
        netstat -tan | tee -a ${K8S_LOGFILE};
        info "DEBUG - SYSENV Information"
        env | tee -a ${K8S_LOGFILE};
        info "DEBUG - Storage Information"
        df -h | tee -a ${K8S_LOGFILE};
        info "DEBUG - System Activities"
        journalctl | tee -a ${K8S_LOGFILE};
    fi
}

#######################################
# Test script is executed as root.
# Arguments:
#   None
# Returns:
#   1 if not executed as root
#######################################
function check_root()
{
    if [[ "$(id -u)" -ne 0 ]]; then
        warn "This script must be run as root"
        exit 1
    else
        info "Root privileges validated"
    fi
}

#######################################
# Configure system environment and
# Download required packages for K8S
# Arguments:
#   None
# Returns:
#   0 if completed, non-zero on error
#######################################
function kube_setup()
{
    info "Creating setup directory"
    mkdir --parents ${K8S_INSTALL_DIR}

    # Install prerequisited packages
    info "K8S Repository keyring set up..."
    apt update &>/dev/null
    apt install --quiet --yes curl apt-transport-https &>/dev/null
    # DEPRECATED - eval "curl -s ${K8S_REPO_KEY} | apt-key add -"
    curl --silent ${K8S_REPO_KEY} | tee /etc/apt/trusted.gpg.d/kubernetes.gpg &>/dev/null
    echo "deb https://apt.kubernetes.io/ ${K8S_APT_DIST} main" | tee /etc/apt/sources.list.d/kubernetes.list &>/dev/null
    apt update &>/dev/null
    info "K8S Repository updated successfully"

    info "Installing K8S Packages..."
    apt install --quiet --yes  git kubelet kubeadm kubectl &>/dev/null
    apt-mark hold kubelet kubeadm kubectl &>/dev/null
    if [[ ! $(which kubectl) ]] || [[ ! $(which kubeadm) ]]; then
        error "K8S Packages not installed !"
        error "View ${K8S_LOGFILE} for more details"
        exit 1
    fi
    info "K8S Packages installed successfully"

    info "Turning off swap..."
    sed --regexp-extended --in-place 's/^(\/swap\.img.*)/#\1/g' /etc/fstab
    swapoff --all
    if [[ $? -ne 0  ]]; then
        error "Turning off swap FAILED - Error: $?"
        exit $?
    fi
    mount --all
    info "Swap turned off successfully"

    info "Enabling networking kernel modules..."
    info "Configuring kernel environment..."
    modprobe overlay
    modprobe br_netfilter
    tee /etc/sysctl.d/kubernetes.conf << EOF
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
EOF

    sysctl --system &>/dev/null
    if [[ $? -ne 0 ]]; then
        error "Kernel configuration FAILED - Error: $?"
        exit $?
    fi
    info "Networking kernel modules enabled successfully"
}

#######################################
# Setting Docker Engine as container runtime
# Arguments:
#   None
# Returns:
#   0 if completed, non-zero on error
#######################################
function docker_setup()
{
    info "Setting up Docker installation repository..."
    apt update &>/dev/null
    apt install --quiet --yes ca-certificates gnupg lsb-release &>/dev/null
    if [[ $? -ne 0 ]]; then
        error "Docker required packages installation FAILED - Error: $?"
        exit $?
    fi
    mkdir --parents /etc/apt/keyrings
    curl --silent --fail --location ${DOCKER_APT_KEY} | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    source_list="deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
    echo ${source_list} | tee /etc/apt/sources.list.d/docker.list &>/dev/null
    apt update &>/dev/null
    info "Docker Repository configured successfully"
 
    info "Downloading and Installing Docker Packages..."
    apt install --quiet --yes docker-ce docker-ce-cli containerd.io docker-compose-plugin &>/dev/null
    if [[ $? -ne 0 ]]; then
        error "Repository set up tools installation FAILED - Error: $?"
        exit $?
    fi
    info "Testing Docker Set up ..."
    docker run hello-world &>/dev/null
    if [[ $? -ne 0 ]]; then
        error "Docker Test FAILED - Error: $?"
        exit $?
    fi
    info "Docker Packages installed successfully"

    info "Configuring Docker as a Service..."
    mkdir --parents /etc/systemd/system/docker.service.d
    info "Configuring Docker Daemon logging"
    tee /etc/docker/daemon.json << EOF
{
"exec-opts": ["native.cgroupdriver=systemd"],
"log-driver": "json-file",
"log-opts": {
    "max-size": "100m"
},
"storage-driver": "overlay2"
}
EOF

    info "Starting and Enabling Docker Service..."
    systemctl daemon-reload &>/dev/null
    systemctl restart docker &>/dev/null
    if [[ $? -ne 0 ]]; then
        error "Activating Docker as a service FAILED - Error: $?"
        exit $?
    fi
    systemctl enable docker &>/dev/null
    info "Docker Service configured successfully"
}

#######################################
# Install MIRANTIS cri-dockerd as shim interface
# Mirantis cri-dockerd is an adapter created to provide a shim for Docker Engine
# to control Docker Engine via the Kubernetes Container Runtime Interface (CRI). 
# Kubernetes has deprecated Docker as a container runtime after v1.20. 
#
# Arguments:
#   None
# Returns:
#   0 if completed, non-zero on error
#######################################
function mirantis_setup()
{
    MIRANTIS_LATEST="https://api.github.com/repos/Mirantis/cri-dockerd/releases/latest"
    MIRANTIS_REPO="https://github.com/Mirantis/cri-dockerd/releases/download"
    MIRANTIS_RAW="https://raw.githubusercontent.com/Mirantis/cri-dockerd/master/packaging/systemd"

    info "Getting MIRANTIS Docker-CRI Binaries"
    DOCKER_CRI_VERSION=$(curl --silent ${MIRANTIS_LATEST} | grep tag_name | cut -d '"' -f 4 | sed 's/v//g')
    wget --quiet ${MIRANTIS_REPO}/v${DOCKER_CRI_VERSION}/cri-dockerd-${DOCKER_CRI_VERSION}}.amd64.tgz \
        --output-document=${K8S_INSTALL_DIR}/cri-dockerd-${VEDOCKER_CRI_VERSION}}.amd64.tgz
    tar --extract --gzip --file=${K8S_INSTALL_DIR}/cri-dockerd-${VEDOCKER_CRI_VERSION}}.amd64.tgz --directory=${K8S_INSTALL_DIR}
    mv ${K8S_INSTALL_DIR}/cri-dockerd/cri-dockerd /usr/local/bin
    if [[ ! $(which cri-dockerd) ]] ; then
        error "MIRANTIS CRI-Dockerd Packages not installed !"
        error "View ${K8S_LOGFILE} for more details"
        exit 1
    fi

    info "Getting CRI Docker Service Files"
    wget --quiet ${MIRANTIS_RAW}/cri-docker.service --output-document=${K8S_INSTALL_DIR}/cri-docker.service
    wget --quiet ${MIRANTIS_RAW}/cri-docker.socket --output-document=${K8S_INSTALL_DIR}/cri-docker.socket
    if [[ $? -ne 0 ]]; then
        error "CRI Docker Service Files Download FAILED - Error: $?"
        exit $?
    fi

    info "Starting CRI Docker Service"
    mv ${K8S_INSTALL_DIR}/cri-docker.socket ${K8S_INSTALL_DIR}/cri-docker.service /etc/systemd/system/
    sed --in-place 's,/usr/bin/cri-dockerd,/usr/local/bin/cri-dockerd,' /etc/systemd/system/cri-docker.service
    systemctl daemon-reload &>/dev/null
    if [[ $? -ne 0 ]]; then
        error "Activating CRI Docker as a service FAILED - Error: $?"
        exit $?
    fi
    systemctl enable cri-docker.service &>/dev/null
    systemctl enable --now cri-docker.socket &>/dev/null
    # TODO - Failed authentication solved using cmd $ sudo usermod -aG docker "${USER}"
    info "CRI Docker Service is UP and RUNNING"
}

#######################################
# Bootstrap cluster master node
# Arguments:
#   None
# Returns:
#   0 if completed, non-zero on error
#######################################
function init_master_node()
{
    info "Initializing K8S Master Node"

    # br_netfilter module is required to enable transparent masquerading and 
    # to facilitate Virtual Extensible LAN (VxLAN) traffic for communication 
    # between Kubernetes pods across the cluster nodes.
    info "Checking 'br_netfilter' Kernel module is loaded"
    eval "lsmod | grep -q '^br_netfilter'"
    if [[ $? -ne 0 ]]; then
        error "Kernel module 'br_netfilter' is NOT LOADED - Error: $?"
        exit $?
    fi
    systemctl enable kubelet &>/dev/null
    kubeadm config images pull --cri-socket unix:///run/cri-dockerd.sock &>/dev/null

    info "Bootstrap cluster without using DNS endpoint"
    kubeadm init --pod-network-cidr=${K8S_POD_NET} --cri-socket=unix:///run/cri-dockerd.sock | tee ${K8S_INSTALL_DIR}/node.install &>/dev/null
    if [[ $? -ne 0 ]]; then
        error "Cluster Bootstrap with kubeadm has FAILED - Error: $?"
        exit $?
    fi
    info "Container runtime endpoint is configured in '/var/lib/kubelet/kubeadm-flags.env'"
    info "Instructions to join worker nodes '${K8S_INSTALL_DIR}/node.install'"

    ## N.B. - Join Token is valid for two hours, use the following commands to generate new one
    ## $ kubeadm token generate | kubeadm token create --print-join-command

    info "Configuring K8S command-line tool to control the cluster"
    mkdir -p $HOME/.kube
    cp /etc/kubernetes/admin.conf $HOME/.kube/config
    chown $(id --user):$(id --group) $HOME/.kube/config
    info "Testing kubectl configuration ..."
    kubectl cluster-info &>/dev/null
    if [[ $? -ne 0 ]]; then
        error "Configuration of kubectl has FAILED - Error: $?"
        error "For more details, use command : 'kubectl cluster-info dump'"
        exit $?
    fi
}


#######################################
# Install network plugin on Master
# Current setup uses CALICO network plugins
# Arguments:
#   None
# Returns:
#   0 if completed, non-zero on error
#######################################
function netplugin_setup()
{
    info "Creating pods to manage cluster via CALICO Network Plugin"
    # TODO - To be executed as ${USER} in charge of cluster control as initialized in master bootstrap
    kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.25.0/manifests/tigera-operator.yaml &>/dev/null
    kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.25.0/manifests/custom-resources.yaml &>/dev/null
    if [[ $(kubectl get nodes -o wide | grep ${HOSTNAME} | wc -l) -ne 1 ]]; then
        error "Creation of Calico Pods has FAILED"
        exit 1
    fi
    info "Calico Network Plugin is ready"
    info "More about nodes using 'watch kubectl get pods --all-namespaces'"

    info "Testing master node is ready..."
    K8S_MASTER_STATUS=$(kubectl get nodes -o wide | grep master | awk '{ print $2 }')
    if [[ ${K8S_MASTER_STATUS} != "Ready" ]]; then 
        error "K8S Master Node is not ready - Master status is ${K8S_MASTER_STATUS}"
        exit 1
    fi
}


#######################################
# MAIN SCRIPT CORE
# Arguments:
#   See usage()
# Returns:
#   0 if completed, non-zero on error
#######################################
while [[ $# > 0 ]]; do
	ARG="$1"
	case $ARG in
	-d|--debug)
		DEBUG_ON=1
		;;
    -m|--install-master)
        INSTALL_MASTER=1
        ;;
    -w|--install-worker)
        INSTALL_WORKER=1
        ;;
	-h|--help)
		USAGE=1
		;;
	-v|--version)
		VERSION=1
		;;
	*)
		error "Unknonw argument, aborting ..."
		exit 128
		;;
	esac
	shift
done

if [[ $USAGE = 1 ]]; then
	usage
elif [[ $VERSION = 1 ]]; then
	show_version
elif [[ $INSTALL_MASTER = 1 && $INSTALL_WORKER != 1 ]]; then
    K8S_NODE_TYPE="MASTER"
    log_header
    check_root
    debug_mode
    kube_setup
    docker_setup
    mirantis_setup
    init_master_node
    netplugin_setup
    log_footer
elif [[ $INSTALL_MASTER != 1 && $INSTALL_WORKER = 1 ]]; then
    K8S_NODE_TYPE="WORKER"
    log_header
    check_root
    debug_mode
    kube_setup
    docker_setup
    mirantis_setup
    ## TODO - To be completed
    log_footer
else
    error "Invalid arguments, aborting ..."
    usage
fi

### EOF ###
