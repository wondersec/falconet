#!/bin/bash
#

function color_log() 
{
  if [[ "$(echo "$2" | grep "false")" = "" || "${@^^}" =~ "ERROR" ]]; then
    echo -e "[\033[31m $@ \033[0m]"
    exit 1
  else
    echo -e "$@"
  fi
}

function prepare_check() {
  isRoot=`id -u -n | grep root | wc -l`
  if [ "x$isRoot" != "x1" ]; then
    echo -e $"[\033[31m ERROR \033[0m] Please use root to execute the installation script (请用 root 用户执行安装脚本)"
    exit 1
  fi
  processor=`cat /proc/cpuinfo| grep "processor"| wc -l`
  #processor=4
  if [ $processor -lt 2 ]; then
    echo -e "[\033[31m ERROR \033[0m] The CPU is less than 2 cores (CPU 小于 2核，Falconet 所在机器的 CPU 需要至少 2核)"
    exit 1
  fi
  memTotal=`cat /proc/meminfo | grep MemTotal | awk '{print $2}'`
  #memTotal=15000000
  if [ $memTotal -lt 7500000 ]; then
    echo -e "[\033[31m ERROR \033[0m] Memory less than 8G (内存小于 8G，Falconet 所在机器的内存需要至少 8G)"
    exit 1
  fi
}

function install_soft() {
  if command -v dnf > /dev/null; then
  if [ "$1" == "python" ]; then
    dnf -q -y install python2
    ln -s /usr/bin/python2 /usr/bin/python
  else
    dnf -q -y install $1
  fi
  elif command -v yum > /dev/null; then
  yum -q -y install $1
  elif command -v apt > /dev/null; then
  apt-get -qqy install $1
  elif command -v zypper > /dev/null; then
  zypper -q -n install $1
  elif command -v apk > /dev/null; then
  apk add -q $1
  else
  echo -e "[\033[31m ERROR \033[0m] Please install it first (请先安装) $1 "
  exit 1
  fi
}

function prepare_install() {
  for i in curl wget zip python; do
    command -v $i &>/dev/null || install_soft $i
  done
}

function config_docker() {
  if [ ! -f "/etc/docker/daemon.json" ]; then
    mkdir -p /etc/docker/
    wget -qO /etc/docker/daemon.json https://wondersec.falconet.org/download/docker/daemon.json || {
    rm -f /etc/docker/daemon.json
    }
  fi
}

function get_package() {
  Version=$(curl -s 'https://api.github.com/repos/wondersec/falconet/releases/latest' | grep "tag_name" | head -n 1 | awk -F ":" '{print $2}' | sed 's/\"//g;s/,//g;s/ //g')
  cd /opt
  if [ ! -d "/opt/falconet-$Version" ]; then
    wget -qO falconet-$Version.tar.gz https://api.github.com/repos/wondersec/falconet/releases/download/$Version/falconet-$Version.tar.gz || {
    rm -rf /opt/falconet-$Version.tar.gz
    echo -e "[\033[31m ERROR \033[0m] Failed to download Falconet (下载 Falconet 失败, 请检查网络是否正常或尝试重新执行脚本)"
    exit 1
    }
    tar -xf /opt/falconet-$Version.tar.gz -C /opt || {
    rm -rf /opt/falconet-$Version
    echo -e "[\033[31m ERROR \033[0m] Failed to unzip Falconet (解压 Falconet 失败, 请检查网络是否正常或尝试重新执行脚本)"
    exit 1
    }
    rm -rf /opt/falconet-$Version.tar.gz
  fi
}

function install() {
  cd /opt/falconet-$Version
  SMC_Version=$(curl -s 'https://api.github.com/repos/wondersec/falconet/releases/latest' | grep "tag_name" | head -n 1 | awk -F ":" '{print $2}' | sed 's/\"//g;s/,//g;s/ //g')
  # sed -i "s/VERSION=.*/VERSION=$SMC_Version/g" /opt/falconet-$Version/version.ini
  ./scripts/install.sh --path=/home/setup
}

function main(){
  prepare_check
  prepare_install
  # config_docker
  get_package
  install
}

main
