#!/bin/sh

# This program is free software. It comes without any warranty, to
# the extent permitted by applicable law. You can redistribute it
# and/or modify it under the terms of the Do What The Fuck You Want
# To Public License, Version 2, as published by Sam Hocevar. See
# http://sam.zoy.org/wtfpl/COPYING for more details.

set -e

# Set this to a non-empty value to enable trace output (for debugging)
TRACE="yep"

trace () {
  if test -n "$TRACE"
  then
    echo "[TRACE] $*"
  fi
}

# This script expects to be run as root. If we're not root, bail out.
UID=$(id -u)
if test x$UID != x0
then
  echo This script must be run as root.
  exit 1
fi

# OS detection
OS=$(uname)

if test x$OS = xLinux
then
  if test -f "/etc/redhat-release"
  then
    DIST="redhat"
  elif test -f "/etc/debian_version"
  then
    DIST="debian"
  else
    DIST="unknown"
  fi
fi

OSMESSAGE="Seems to be $OS"
if test -n "$DIST"
then
  OSMESSAGE="$OSMESSAGE ($DIST)"
fi
trace $OSMESSAGE

# Define text styles
BOLD=""
DIM=""
NORMAL=""

if tput bold > /dev/null
then
  BOLD=$(tput bold)
fi

if tput dim > /dev/null
then
  DIM=$(tput dim)
fi

if tput sgr0 > /dev/null
then
  NORMAL=$(tput sgr0)
fi

if test -z "$BOLD" -o -z "$NORMAL"
then
  trace "No support for bold text."
  BOLD=""
fi

if test -z "$DIM" -o -z "$NORMAL"
then
  trace "No support for dim text."
  DIM=""
fi

if test -z "$BOLD" -a -z "$DIM"
then
  NORMAL=""
fi

create_account () {
  echo "${BOLD}(1/4) Creating account \"storage\"...${NORMAL}"
  
  if [ `grep "^storage:" /etc/passwd | cut -b -7` = "storage" ]; then
    echo " -> Account already exists."
  else
    echo "${DIM} -> useradd storage --create-home --user-group${NORMAL}"
    useradd storage --create-home --user-group
  fi
  
  sleep 0.5
}

configure_ssh () {
  echo "${BOLD}(2/4) Configuring account \"storage\"...${NORMAL}"
  
  echo "${DIM} -> mkdir /home/storage/.ssh${NORMAL}"
  mkdir -p /home/storage/.ssh
  
  echo "${DIM} -> touch /home/storage/.ssh/authorized_keys${NORMAL}"
  touch /home/storage/.ssh/authorized_keys

  echo "${DIM} -> chmod 700 /home/storage/.ssh${NORMAL}"
  chmod 700 /home/storage/.ssh
  
  echo "${DIM} -> chmod 600 /home/storage/.ssh/authorized_keys${NORMAL}"
  chmod 600 /home/storage/.ssh/authorized_keys

  CONFIG_CHECK=`grep "^# SparkleShare$" /etc/ssh/sshd_config`
  if ! [ "$CONFIG_CHECK" = "# SparkleShare" ]; then
    echo "" >> /etc/ssh/sshd_config
    echo "# SparkleShare" >> /etc/ssh/sshd_config
    echo "Match User storage" >> /etc/ssh/sshd_config
    echo "    PasswordAuthentication no" >> /etc/ssh/sshd_config
  fi
  
  sleep 0.5
}

restart_ssh () {
  echo "${BOLD}(3/4) Restarting SSH service...${NORMAL}"
  
  if [ "$OS" = "redhat" ]; then
    echo " -> /etc/init.d/sshd restart"
    /etc/init.d/sshd restart >/dev/null
  else
    echo " -> /etc/init.d/ssh restart"
    /etc/init.d/ssh restart >/dev/null
  fi
}

install_git () {
  echo "${BOLD}(4/4) Installing Git package...${NORMAL}"

  if [ -f "/usr/bin/git" ]; then
    GIT_VERSION=`/usr/bin/git --version | cut -b 13-`
    echo " -> Git package has already been installed (version $GIT_VERSION)."
  else 
    if [ "$OS" = "redhat" ]; then
      echo " -> yum -y install git"
      yum -y install git
    else
      echo " -> apt-get -y install git"
      apt-get -yq install git-core
    fi
  fi
}

create_project () {
  echo "${BOLD}Creating project \"$1\"...${NORMAL}"

  if [ -f "/home/storage/$1/HEAD" ]; then
    echo " -> Project \"$1\" already exists."
    echo
  else
    echo " -> git init --bare /home/storage/$1"
    git init --quiet --bare /home/storage/$1
    
    echo " -> chown -R storage:storage /home/storage"
    chown -R storage:storage /home/storage

    sleep 0.5

    echo 
    echo "${BOLD}Project \"$1\" was successfully created.${NORMAL}"
  fi

  PORT=`grep "^Port 22$" /etc/ssh/sshd_config | cut -b 6-`
  if [ "$PORT" = "22" ]; then
    PORT=""
  else
    CUSTOM_PORT=`grep "^Port " /etc/ssh/sshd_config | cut -b 6-`
    PORT=":$CUSTOM_PORT"
  fi

  IP=`curl --silent http://ifconfig.me/ip`

  echo "To link up a SparkleShare client, enter the following"
  echo "details into the ${BOLD}\"Add Hosted Project...\"${NORMAL} dialog: "
  echo 
  echo "      Address: ${BOLD}storage@$IP$PORT${NORMAL}"
  echo "  Remote Path: ${BOLD}/home/storage/$1${NORMAL}"
  echo
  echo "To link up (more) computers, use the \"dazzle link\" command."
  echo
}

link_client () {
  echo "Paste the contents of ${BOLD}\"~/SparkleShare/Your Name's link code.txt\"${NORMAL}"
  echo "(found on the client) into the field below and press ${BOLD}<ENTER>${NORMAL}."
  echo 
  echo -n "${BOLD}Link code: ${NORMAL}"
  read LINK_CODE
  
  if [ ${#SHELL} > 256 ]; then
    echo $LINK_CODE >> /home/storage/.ssh/authorized_keys
    echo
    echo "${BOLD}The client with this link code can now access projects.${NORMAL}"
    echo Repeat this step to link more clients.
    echo
  else
    echo "${BOLD}Not a valid link code...${NORMAL}"
  fi
}

# Parse the command line arguments
case $1 in
  setup)
    create_account
    configure_ssh
    restart_ssh
    install_git
    echo
    echo "${BOLD}Setup complete!${NORMAL}"
    echo "To create a new project, run \"dazzle create PROJECT_NAME\"."
    echo
    ;;
  create)
    create_project $2
    ;;
  create-encrypted)
    create_project $2-crypto
    ;;
  link)
    link_client $2
    ;;
  *|help)
    echo "${BOLD}Dazzle, SparkleShare host setup script${NORMAL}"
    echo
    echo "Usage: dazzle [COMMAND]"
    echo 
    echo "COMMAND can be one of the following:"
    echo
    echo "  setup"
    echo "    configures this machine to serve as a SparkleShare host"
    echo
    echo "  create PROJECT_NAME"
    echo "    creates a SparkleShare project called PROJECT_NAME"
    echo
    echo "  create-encrypted PROJECT_NAME"
    echo "    creates an encrypted SparkleShare project"
    echo
    echo "  link"
    echo "    links a SparkleShare client to this host by entering a link code"
    echo
    echo "  help"
    echo "    show this help message"
    echo
    ;;
esac
