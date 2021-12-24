#!/bin/bash
# curl -sSL https://github.com/wondersec/falconet/releases/latest/download/quick_start.sh | sh
################################

function color_log() 
{
  if [[ "$(echo "$2" | grep "false")" != "" || "${@^^}" =~ "ERROR" ]]; then
    echo -e "[\033[31m $@ \033[0m]"
    exit 1
  else
    echo -e "$@"
  fi
}

function prepare_check() 
{
  isRoot=`id -u -n | grep root | wc -l`
  if [ "x$isRoot" != "x1" ]; then
    echo -e $"[\033[31m ERROR \033[0m] Please use root to execute the installation script ."
    exit 1
  fi
  processor=`cat /proc/cpuinfo| grep "processor"| wc -l`
  #processor=4
  if [ $processor -lt 2 ]; then
    echo -e "[\033[31m ERROR \033[0m] The CPU is less than 2 cores ."
    exit 1
  fi
  memTotal=`cat /proc/meminfo | grep MemTotal | awk '{print $2}'`
  #memTotal=85000000
  if [ $memTotal -lt 7500000 ]; then
    echo -e "[\033[31m ERROR \033[0m] Memory less than 8G ."
    exit 1
  fi
}

function install_soft() 
{
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
    echo -e "[\033[31m ERROR \033[0m] Please install it first $1 "
    exit 1
  fi
}

function prepare_install() 
{
  for i in curl cpio zip; do # python wget
    command -v $i &>/dev/null || install_soft $i
  done
}

function config_docker() 
{
  if [ ! -f "/etc/docker/daemon.json" ]; then
    mkdir -p /etc/docker/
    wget -qO /etc/docker/daemon.json https://www.wondersec.org/falconet/download/docker/daemon.json || {
      rm -f /etc/docker/daemon.json
    }
  fi
}

function download_package() 
{
  falconet_url=http://www.wondersec.com/falconet/download
  if [[ -n "$1" && ! -f "$1" ]]; then
    color_log $"download $1: $falconet_url/$1"
    curl -LOk "$falconet_url/$1" || {
      echo -e "[\033[31m ERROR \033[0m] Failed to download the $1 package. Please check whether the network is normal or try to execute the script again."
      rm -f $1
      exit 1
    }
  fi
  extract_package $1 $2
}

function download_clickhouse() 
{
  clickhouse_version=21.8.11.4
  clickhouse_path=$1/clickhouse
  clickhouse_url=https://repo.yandex.ru/clickhouse/rpm/lts/x86_64
  clickhouse_rpms=("clickhouse-common-static-${clickhouse_version}-2.x86_64.rpm" \
    "clickhouse-server-${clickhouse_version}-2.noarch.rpm" \
    "clickhouse-client-${clickhouse_version}-2.noarch.rpm" )
  # "clickhouse-common-static-dbg-${clickhouse_version}-2.x86_64.rpm"
  # "clickhouse-test-${clickhouse_version}-2.noarch.rpm"
  for rpm_name in ${clickhouse_rpms[@]}; do
    if [ ! -f ${rpm_name} ]; then
      color_log $"download ${rpm_name}: ${clickhouse_url}/${rpm_name}"
      curl -LOk "${clickhouse_url}/${rpm_name}" || {
        rm -rf ${rpm_name}
        echo -e "[\033[31m ERROR \033[0m] Failed to download ${rpm_name}, Please check whether the network is normal or try to execute the script again."
        exit 1
      }
      rpm2cpio ${rpm_name} | cpio -di || {
        rm -rf ${rpm_name}
        echo -e "[\033[31m ERROR \033[0m] Failed to extract the ${rpm_name} package. Please try to execute the installation command again."
        exit 1
      }
      rm -rf ${rpm_name}
    fi
  done
  mkdir -p $clickhouse_path
  if [[ -d "usr/bin/" ]]; then
    /usr/bin/mv -f usr/bin $clickhouse_path/bin
    /usr/bin/mv -f usr/share $clickhouse_path/share
    /usr/bin/mv -f etc/clickhouse-server $clickhouse_path/config
    /usr/bin/mv -f etc/clickhouse-client/config.xml $clickhouse_path/config/client.xml
  fi
}

function extract_package() 
{
  color_log $"extract $1 to $2"
  extension="${1##*.}"
  illegal=1
  if [ "zip" == "${extension}" ]; then
    unzip -o $1 -d $2 && illegal=$?
  elif [ "gz" == "${extension}" ]; then
    tar zxf $1 -C $2 && illegal=$?
  elif [ "xz" == "${extension}" ]; then
    tar xJf $1 -C $2 && illegal=$?
  else
    tar xf $1 -C $2 && illegal=$?
  fi
  rm -f $1
  if [ $illegal != 0 ];then
    echo -e "[\033[31m ERROR \033[0m] Failed to extract the $1 package. Please try to execute the installation command again."
    exit 1
  fi
  return $illegal
}

function install() 
{
  cd /opt/
  # SMC_Version=$(curl -s 'https://api.github.com/repos/wondersec/falconet/releases/latest' | grep "tag_name" | head -n 1 | awk -F ":" '{print $2}' | sed 's/\"//g;s/,//g;s/ //g')
  # sed -i "s/VERSION=.*/VERSION=$SMC_Version/g" /opt/falconet-$Version/version.ini
  # ./scripts/install.sh --path=/home/setup
  install_path=/data/falconet
  if [ ! -d ${install_path} ]; then
    mkdir -p ${install_path}
  fi
  script_path=${install_path}/scripts
  package_name=falconet-server.tar.xz
  # download server
  download_package ${package_name} ${install_path}
  version_file=$script_path/config/version.ini
  if [ -f $version_file ]; then
    sed '/^#/d' $version_file | sed 's/=/\n=/g' | sed '/^[^=#]/s/[.]/_/g' | sed '/^[^#]/{N;s/\n//}' > $script_path/version.ini
    source $script_path/version.ini
    rm -rf $script_path/version.ini
  else
    echo -e "[\033[31m ERROR \033[0m] Failed to download the $version_file package. Please try to execute the installation command again."
    exit 1
  fi
  # download java
  download_package falconet-java.tar.xz ${install_path}
  # download db
  if [ ${db_instances} -gt 0 ]; then
    download_package falconet-db.tar.xz ${install_path}
  fi
  # download es
  if [ ${es_instances} -gt 0 ]; then
    download_package falconet-es.tar.xz ${install_path}
  fi
  # download zk
  if [ ${zk_instances} -gt 0 ]; then
    download_package falconet-zk.tar.xz ${install_path}
  fi
  # download ck
  if [ ${ck_instances} -gt 0 ]; then
    download_clickhouse ${install_path}
  fi
  $script_path/install.sh -q --path=${install_path}
}

function main(){
  prepare_check
  prepare_install
  # config_docker
  install
}

main
