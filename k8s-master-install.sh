#!/bin/bash -x
#@file
# KUBERNETES Master node setup process automation
#
# NOTE ! This script expects to be running as under ROOT ID
#
# Sources
# - https://kubernetes.io/docs/setup/production-environment/
# - https://computingforgeeks.com/deploy-kubernetes-cluster-on-ubuntu-with-kubeadm/

########################
### WORK IN PROGRESS ###
########################

###
### GLOBALS
###
DEBUG_ON=0
K8S_EXITCODE=0
K8S_LOG_FILE="/var/log/k8s-install.log"
K8S_CORE="kubernetes-1.26.2"
K8S_REPO_KEY="https://packages.cloud.google.com/apt/doc/apt-key.gpg"
K8S_APT_DIST="kubernetes-xenial"
K8S_USER="k8s-master"
K8S_GROUP="kubernetes"
K8S_INSTALL_DIR="/opt/k8s-master"
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
    blog "** K8S Master Node Installation - Unattended installation "
    blog "** Date:    `date -R`"
    blog "** Started: $0 $*"
    blog ""
}

#
# Log footer.
#
function log_footer()
{
    blog "**************************************************************"
    blog "** Date:            `date -R`"
    blog "** Final exit code: ${MY_EXITCODE}"
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

###
### Testing privileges required
###
function check_root()
{
    if [[ "$(id -u)" -ne 0 ]]; then
        warn "This script must be run as root" >&2
        exit 1
    else
        info "Root privileges validated"
    fi
}

###
### Setup system environment
###
function env_setup()
{
    info "Creating setup directory"
    mkdir -p ${K8S_INSTALL_DIR}

    # Install prerequisited packages
    info "K8S Repository keyring set up..."
    apt update &>/dev/null
    apt install -qq -y curl apt-transport-https
    # DEPRECATED - eval "curl -s ${K8S_REPO_KEY} | apt-key add -"
    curl -s ${K8S_REPO_KEY} | tee /etc/apt/trusted.gpg.d/kubernetes.gpg
    echo 'deb https://apt.kubernetes.io/ ${K8S_APT_DIST} main' | tee /etc/apt/sources.list.d/kubernetes.list &>/dev/null
    apt update &>/dev/null
    info "K8S Repository updated successfully"


    info "Installing K8S Packages..."
    apt install -qq -y  git kubelet kubeadm kubectl &>/dev/null
    apt-mark hold kubelet kubeadm kubectl &>/dev/null
    if [! which kubectl &>/dev/null] || [! which kubeadm &>/dev/null]  ; then
        error "K8S Packages not installed !" 1>&2
        error "View ${K8S_LOGFILE} for more details" 1>&2
        exit 1
    fi
    info "KK8S Packages installed successfully"

    info "Turning off swap..."
    sed -r -i 's/^(\/swap\.img.*)/#\1/g' /etc/fstab
    swapoff -a
    if [ ! $? -eq 0 ]; then
        error "Turning off swap FAILED - Error: $?\n" 1>&2
        exit $?
    fi
    mount -a
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
    if [ ! $? -eq 0 ]; then
        error "Kernel configuration FAILED - Error: $?" 1>&2
        exit $?
    fi
    info "Networking kernel modules enabled successfully"
}

###
### Setting Docker Engine as container runtime
### 
function docker_setup()
{
    info "Setting up Docker installation repository..."
    apt update &>/dev/null
    apt install -qq -y ca-certificates gnupg lsb-release &>/dev/null
    if [ ! $? -eq 0 ]; then
        error "Docker required packages installation FAILED - Error: $?" 1>&2
        exit $?
    fi
    mkdir -p /etc/apt/keyrings
    curl -fsSL ${DOCKER_APT_KEY} | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    source_list="deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
    echo ${source_list} | tee /etc/apt/sources.list.d/docker.list &>/dev/null
    info "Docker Repository configured successfully"
 
    info "Downloading and Installing Docker Packages..."
    apt update &>/dev/null
    apt install -qq -y docker-ce docker-ce-cli containerd.io docker-compose-plugin &>/dev/null
    if [ ! $? -eq 0 ]; then
        error "Repository set up tools installation FAILED - Error: $?" 1>&2
        exit $?
    fi
    info "Testing Docker Set up ..."
    docker run hello-world &>/dev/null
    if [ ! $? -eq 0 ]; then
        error "Docker Test FAILED - Error: $?" 1>&2
        exit $?
    fi
    info "Docker Packages installed successfully"

    info "Configuring Docker as a Service..."
    mkdir -p /etc/systemd/system/docker.service.d
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
    systemctl daemon-reload 
    systemctl restart docker
    if [ ! $? -eq 0 ]; then
        error "Activating Docker as a service FAILED - Error: $?"
        exit $?
    fi
    systemctl enable docker
    info "Docker Service configured successfully"
}

### Install MIRANTIS cri-dockerd as shim interface
### Mirantis cri-dockerd is an adapter created to provide a shim for Docker Engine
### to control Docker Engine via the Kubernetes Container Runtime Interface (CRI). 
### Kubernetes has deprecated Docker as a container runtime after v1.20. 
function mirantis_setup()
{
    info "Getting MIRANTIS Docker-CRI Binaries"
    DOCKER_CRI_VERSION=$(curl -s https://api.github.com/repos/Mirantis/cri-dockerd/releases/latest | grep tag_name | cut -d '"' -f 4 | sed 's/v//g')
    wget -q https://github.com/Mirantis/cri-dockerd/releases/download/v${DOCKER_CRI_VERSION}/cri-dockerd-${.DOCKER_CRI_VERSION}}.amd64.tgz -O ${K8S_INSTALL_DIR}/cri-dockerd-${VEDOCKER_CRI_VERSION}}.amd64.tgz
    tar -zxf ${K8S_INSTALL_DIR}/cri-dockerd-${VEDOCKER_CRI_VERSION}}.amd64.tgz
    mv ${K8S_INSTALL_DIR}/cri-dockerd/cri-dockerd /usr/local/bin
    if [ "$(which cri-dockerd)" != "0" ] ; then
        error "MIRANTIS CRI-Dockerd Packages not installed !" 1>&2
        error "View ${K8S_LOGFILE} for more details" 1>&2
        exit 1
    fi

    info "Getting CRI Docker Service Files"
    wget https://raw.githubusercontent.com/Mirantis/cri-dockerd/master/packaging/systemd/cri-docker.service -O ${K8S_INSTALL_DIR}/cri-docker.service
    wget https://raw.githubusercontent.com/Mirantis/cri-dockerd/master/packaging/systemd/cri-docker.socket -O ${K8S_INSTALL_DIR}/cri-docker.socket
    if [ ! $? -eq 0 ]; then
        error "CRI Docker Service Files Download FAILED - Error: $?" 1>&2
        exit $?
    fi

    info "Starting CRI Docker Service"
    mv ${K8S_INSTALL_DIR}/cri-docker.socket ${K8S_INSTALL_DIR}/cri-docker.service /etc/systemd/system/
    sed -i -e 's,/usr/bin/cri-dockerd,/usr/local/bin/cri-dockerd,' /etc/systemd/system/cri-docker.service
    systemctl daemon-reload
    if [ ! $? -eq 0 ]; then
        error "[${RED}ERROR${RST}] - Activating CRI Docker as a service FAILED - Error: $?" 1>&2
        exit $?
    fi
    systemctl enable cri-docker.service
    systemctl enable --now cri-docker.socket
    info "CRI Docker Service is UP and RUNNING"

    info "Configure kubelet to use CRI Dockerd"
    kubeadm config images pull --cri-socket /run/cri-dockerd.sock
    kubeadm init --pod-network-cidr=10.244..0.0/16 --cri-socket /run/cri-dockerd.sock

    ## TODO - Migration of worker nodes is to be done 
    ## https://computingforgeeks.com/install-mirantis-cri-dockerd-as-docker-engine-shim-for-kubernetes/

}

##
## Bootstrap cluster master node
##
function init_master_node()
{
    info "Initializing K8S Master Node"

    # br_netfilter module is required to enable transparent masquerading and 
    # to facilitate Virtual Extensible LAN (VxLAN) traffic for communication 
    # between Kubernetes pods across the cluster nodes.
    info "Checking 'br_netfilter' Kernel module is loaded"
    logcommand eval "lsmod | grep -q '^br_netfilter'"
    if [ ! $? -eq 0 ]; then
        error "Kernel module 'br_netfilter' is NOT LOADED - Error: $?\n" 1>&2
        exit $?
    fi
    systemctl enable kubelet
    kuadm config images pull

    info "Bootstrap cluster without using DNS endpoint"
    kubeadm init --pod-network-cidr=10.66.0.0/16 --cri-socket= unix:///run/cri-dockerd.sock &>/dev/null
    if [ ! $? -eq 0 ]; then
        error "Cluster Bootstrap with kubeadm has FAILED - Error: $?\n" 1>&2
        exit $?
    fi

    info "Configuring K8S command-line tool to control the cluster"
    mkdir -p $HOME/.kube
    cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
    chown $(id -u):$(id -g) $HOME/.kube/config
    info "Testing kubectl configuration ..."
    kubectl cluster-info
    if [ ! $? -eq 0 ]; then
        error "Configuration of kubectl has FAILED - Error: $?\n" 1>&2
        error "For more details, use command : 'kubectl cluster-info dump'"
        exit $?
    fi
}

##
## Install network plugin on Master
## Current setup uses CALICO network plugins
##
function netplugin_setup()
{
    info "Creating pods to manage cluster via CALICO Network Plugin"
    kubectl create -f https://docs.projectcalico.org/manifests/tigera-operator.yaml &>/dev/null
    kubectl create -f https://docs.projectcalico.org/manifests/custom-resources.yaml &>/dev/null
    if [[ $(watch kubectl get pods --all-namespaces | grep calico | wc -l ) -eq 0 ]]; then
        error "Creation of Calico Pods has FAILED" 1>&2
        exit 1
    fi
    info "Calico Network Plugin is ready"

    info "Testing master node is ready..."
    K8S_MASTER_STATUS=$(kubectl get nodes -o wide | grep master | awk '{ print $2 }')
    if [[ $K8S_MASTER_STATUS != "Ready" ]]; then 
        error "K8S Master Node is not ready - Master status is $K8S_MASTER_STATUS" 1>&2
        exit 1
    fi
}


#######################################
### MAIN CORE
while [[ $# > 0 ]]; do
	ARG="$1"
	case $ARG in
	-d|--debug)
		DEBUG_ON=1
		;;
    -i|--install)
        K8S_INSTALL=1
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
else 
    log_header
    check_root
    debug_mode

    ## TODO - To be continued

    log_footer
fi

### EOF ###
