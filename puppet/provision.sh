#!/bin/sh

## On each instance, where can the PE installers be found
## This is the "pe" directory in the vagrant environment
PE_DIR="/vagrant/puppet/pe"

## Versions of PE we need/want
PE_27="2.7.2"
PE_28="2.8.7"
PE_3="3.3.1"

## Some helper functions
function get_pe() {
  PE_VERSION="$1"
  curl -O "https://s3.amazonaws.com/pe-builds/released/${PE_VERSION}/puppet-enterprise-${PE_VERSION}-el-6-x86_64.tar.gz"
}

function verify_pe_tarball() {
  PE_VERSION="$1"
  if [ ! -f "${PE_DIR}/puppet-enterprise-${PE_VERSION}-el-6-x86_64.tar.gz" ]; then
    return 1
  fi
}

function verify_pe_installdir() {
  PE_VERSION="$1"
  if [ ! -d "${PE_DIR}/puppet-enterprise-${PE_VERSION}-el-6-x86_64" ]; then
    return 1
  fi
}

case $1 in
  "master27")
    PEINSTALL="2.7.2"
    ANSWERS="master27.txt"
    ;;
  "master33")
    PEINSTALL="3.3.1"
    ANSWERS="master33.txt"
    ;;
  "agent")
    PEINSTALL="2.7.2"
    ANSWERS="agent27.txt"
    ;;
esac

## Download and extract the PE installer tarball as necessary
cd "$PE_DIR" || (echo "${PE_DIR} doesn't exist!" && exit 1)
for pe in $PE_27 $PE_28 $PE_3; do
  if ! verify_pe_tarball "$pe"; then
    get_pe "$pe" || (echo "Failed to download ${pe}" && exit 1)
  fi

  if ! verify_pe_installdir "$pe"; then
    tar xvf "puppet-enterprise-${pe}-el-6-x86_64.tar.gz" \
      || (echo "Failed to extract ${pe}" && exit 1)
  fi
done

## Sync time right away
echo "==> Syncing time..."
/usr/bin/env ntpdate ntp.org

## Stub out /etc/hosts on each system
cat > /etc/hosts <<EOH
127.0.0.1 localhost localhost.localdomain localhost4 localhost4.localdomain
::1 localhost localhost.localdomain localhost6 localhost6.localdomain
10.0.4.60 master27.vagrant.vm master27
10.0.4.61 tempmaster.vagrant.vm tempmaster
10.0.4.62 master33.vagrant.vm master33
10.0.4.63 agent.vagrant.vm agent
EOH

##
## Install Puppet Enterprise
##
if [ ! -z "${PEINSTALL}" ]; then

  INSTALL_PATH="${PE_DIR}/puppet-enterprise-${PEINSTALL}-el-6-x86_64"
  FILENAME="${PEINSTALL}.tar.gz"

  cd $PE_DIR

  if [ ! -d '/opt/puppet/' ]; then
    ${INSTALL_PATH}/puppet-enterprise-installer \
      -a /vagrant/puppet/answers/${ANSWERS}
  else
    echo "/opt/puppet exists. Assuming it's already installed."
  fi

fi

echo "Disabling iptables.."
service iptables stop
