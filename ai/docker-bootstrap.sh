#!/bin/bash
#
# Bootstrapping a linux box with docker and consul.
#
CONSUL_MASTER_URL="$1"

INSTANCE_ID=""
INSTANCE_PRIV_IP=""
INSTANCE_REGION=""

DOCKER_BIN="/usr/bin/docker"

CONSUL_HOST_DIR="/var/lib/consul"
CONSUL_HOST_CFG_DIR="${CONSUL_HOST_DIR}/config"

CONSUL_DOCKER_IMAGE="gliderlabs/consul"
CONSUL_DOCKER_ARGS="-d -p 8301:8301/udp -p 8302:8302/udp -p 8300:8300/tcp -p 8301:8301/tcp -p 8302:8302/tcp -p 8400:8400 -p 8500:8500 -p 53:53/udp -p 53:53/tcp -v ${CONSUL_HOST_DIR}:/data"
CONSUL_ARGS="agent -node $(hostname) -ui-dir /ui -data-dir /data -config-dir /data/config"
# Only used by consul agents running in containers
CONSUL_DOCKER_AGENT_ARGS="-v /var/run/docker.sock:/var/run/docker.sock"

#### Routines ####

set_consul_retry_join() {
	if [ "${CONSUL_MASTER_URL}" != "" ]; then
		for i in `curl -s "${CONSUL_MASTER_URL}" | jq -r .[].Address`; do 
			CONSUL_ARGS="${CONSUL_ARGS} -retry-join ${i}";
		done
	fi
}

setup_consul_dirs() {
	[ -d "${CONSUL_HOST_CFG_DIR}" ] || mkdir -p "${CONSUL_HOST_CFG_DIR}"
}

install_jq() {
	JQ_URL="https://github.com/stedolan/jq/releases/download/jq-1.5/jq-linux64"
	
	[ -x "/usr/bin/jq" ] || {
		curl -s -O -L ${JQ_URL} && chmod +x jq-linux64 && mv ./jq-linux64 /usr/bin/jq || { echo "Failed to install: jq"; return $?; };
	}
	return $?
}

# User call
consul_agent_cmd() {
	echo "${DOCKER_BIN} run --name consul-agent ${CONSUL_DOCKER_ARGS} ${CONSUL_DOCKER_AGENT_ARGS} ${CONSUL_DOCKER_IMAGE} ${CONSUL_ARGS}"
}

#### Main ####
install_jq

if [ -e /etc/system-release ]; then
  if [ "$(cat /etc/system-release)" == "Amazon Linux AMI release 2016.03" ]; then
    INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
    INSTANCE_PRIV_IP=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)
    #INSTANCE_REGION=$(curl -s http://169.254.169.254/latest/dynamic/instance-identity/document|grep region|awk -F\" '{print $4}')
    INSTANCE_REGION=$(curl -s http://169.254.169.254/latest/dynamic/instance-identity/document|jq -r .region)

    /bin/rpm -qa | grep docker || { /usr/bin/yum -y install docker && /sbin/service docker start; }
    
    CONSUL_ARGS="${CONSUL_ARGS} -dc ${INSTANCE_REGION} -advertise ${INSTANCE_PRIV_IP}"
  fi
fi

setup_consul_dirs

set_consul_retry_join