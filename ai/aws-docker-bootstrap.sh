#!/bin/bash

CONSUL_SERVER_URL="$1"

INSTANCE_ID=""
INSTANCE_PRIV_IP=""
INSTANCE_REGION=""

AWS_CMD="/usr/bin/aws"
DOCKER_BIN="/usr/bin/docker"

# Args used by server and agent
BASE_CONSUL_ARGS="agent -node $(hostname) -client 0.0.0.0"
# -retry-join servers
CONSUL_RETRY_JOINS=""
DEFAULT_CONSUL_DATA_DIR="/var/lib/consul"
DEFAULT_CONSUL_CFG_DIR="${DEFAULT_CONSUL_DATA_DIR}/config"

ASG_NAME=""
ASG_SERVER_CNT=""
ASG_SERVER_IPS=""

install_jq() {
  JQ_URL="https://github.com/stedolan/jq/releases/download/jq-1.5/jq-linux64"
    
  [ -x "/usr/bin/jq" ] || {
      curl -s -O -L ${JQ_URL} && chmod +x jq-linux64 && mv ./jq-linux64 /usr/bin/jq || { 
        echo "Failed to install: jq"; return $?; 
      }
  }
  return $?
}

set_aws_asg_info() {
  # Install aws cli
  if [ ! -e "${AWS_CMD}" ]; then 
    if [ ! -e "/usr/local/bin/pip" ]; then
      easy_install pip
    fi
    /usr/local/bin/pip install awscli
  fi

  ASG_NAME=`${AWS_CMD} autoscaling describe-auto-scaling-instances --region ${INSTANCE_REGION} --instance ${INSTANCE_ID} --query 'AutoScalingInstances[0].AutoScalingGroupName' --output text`

  # Get cluster member count from ASG.
  ASG_SERVER_CNT=`${AWS_CMD} autoscaling describe-auto-scaling-groups --region ${INSTANCE_REGION} --auto-scaling-group-name ${ASG_NAME} --query "AutoScalingGroups[0].DesiredCapacity"`

  for i in `${AWS_CMD} autoscaling describe-auto-scaling-groups --region $INSTANCE_REGION --auto-scaling-group-name $ASG_NAME --query "AutoScalingGroups[0].Instances[].InstanceId" --output text`;do 
      # Get ip address of instance
      ipaddr=$(${AWS_CMD} ec2 describe-instances --region ${INSTANCE_REGION} --instance ${i} --query "Reservations[0].Instances[0].PrivateIpAddress" --output text)

      ASG_SERVER_IPS="${ASG_SERVER_IPS} ${ipaddr}"
  done
}

install_aws_docker() {
  /bin/rpm -qa | grep docker || { /usr/bin/yum -y install docker && /sbin/service docker start; }
}

set_consul_retry_join() {
  if [ "${CONSUL_SERVER_URL}" != "" ]; then
    for i in `curl -s "${CONSUL_SERVER_URL}/v1/catalog/service/consul?dc=${INSTANCE_REGION}" | jq -r .[].Address`; do 
      CONSUL_RETRY_JOINS="${CONSUL_RETRY_JOINS} -retry-join ${i}";
    done
  fi
}

create_consul_dirs() {
  [ -d "${DEFAULT_CONSUL_DATA_DIR}" ] || mkdir ${DEFAULT_CONSUL_DATA_DIR};
  [ -d "${DEFAULT_CONSUL_CFG_DIR}" ] || mkdir ${DEFAULT_CONSUL_CFG_DIR};
}

install_consul_agent() {
  CONSUL_BIN_PKG="consul_0.6.4_linux_amd64.zip"

  curl -s -O "https://releases.hashicorp.com/consul/0.6.4/${CONSUL_BIN_PKG}"
  unzip "${CONSUL_BIN_PKG}"
  mv consul /usr/bin/
  rm -f "${CONSUL_BIN_PKG}"

  # Set only if not currently set
  if [ "${CONSUL_RETRY_JOINS}" == "" ]; then set_consul_retry_join; fi

  cat <<EOF > /etc/init/consul-agent.conf
description "Consul Agent"

start on (local-filesystems and net-device-up IFACE=eth0)
stop on runlevel [!12345]

exec consul ${BASE_CONSUL_ARGS} -data-dir ${DEFAULT_CONSUL_DATA_DIR} -config-dir ${DEFAULT_CONSUL_CFG_DIR} -dc ${INSTANCE_REGION} -advertise ${INSTANCE_PRIV_IP} ${CONSUL_RETRY_JOINS} >> /var/log/consul-agent.log
EOF
}

# helper 
init_consul_agent() {
  install_consul_agent
  /sbin/start consul-agent
}

set_instance_metadata() {
  INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
  INSTANCE_PRIV_IP=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)
  INSTANCE_REGION=$(curl -s http://169.254.169.254/latest/dynamic/instance-identity/document|jq -r .region)
}

#### Main #####

install_jq
create_consul_dirs

if [ -e /etc/system-release ]; then
  if [ "$(cat /etc/system-release)" == "Amazon Linux AMI release 2016.03" ]; then
    set_instance_metadata
    install_aws_docker
  fi
fi
