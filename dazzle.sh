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
  STORAGE=`grep "^storage:" /etc/passwd | cut --bytes=-7`
  if [ "$STORAGE" = "storage" ]; then
    echo " -> Account already exists."
  else
    echo " -> useradd storage --create-home --user-group --shell $GIT_SHELL --password \"*\""
    useradd storage --create-home --user-group --shell $GIT_SHELL --password "*"
  fi
  
  sleep 0.5
}

configure_ssh () {
  echo " -> mkdir --parents /home/storage/.ssh"
  mkdir --parents /home/storage/.ssh
  
  echo " -> touch /home/storage/.ssh/authorized_keys"
  touch /home/storage/.ssh/authorized_keys

  echo " -> chmod 700 /home/storage/.ssh"
  chmod 700 /home/storage/.ssh
  
  echo " -> chmod 600 /home/storage/.ssh/authorized_keys"
  chmod 600 /home/storage/.ssh/authorized_keys

  # Disable the password for the "storage" user to force authentication using a key
  CONFIG_CHECK=`grep "^# SparkleShare$" /etc/ssh/sshd_config`
  if ! [ "$CONFIG_CHECK" = "# SparkleShare" ]; then
    echo "" >> /etc/ssh/sshd_config
    echo "# SparkleShare" >> /etc/ssh/sshd_config
    echo "# Please do not edit the above comment as it's used as a check by Dazzle" >> /etc/ssh/sshd_config
    echo "Match User storage" >> /etc/ssh/sshd_config
    echo "    PasswordAuthentication no" >> /etc/ssh/sshd_config
    echo "    PubkeyAuthentication yes" >> /etc/ssh/sshd_config
  fi
  
  sleep 0.5
}

restart_ssh () {
  if [ -f "/etc/init.d/sshd" ]; then
    echo " -> /etc/init.d/sshd restart"
    /etc/init.d/sshd restart >/dev/null
  elif [ -f "/etc/rc.d/sshd" ]; then
    echo " -> /etc/rc.d/sshd restart"
    /etc/rc.d/sshd restart >/dev/null
  else
    echo " -> /etc/init.d/ssh restart"
    /etc/init.d/ssh restart >/dev/null
  fi
}

install_git () {
  if [ -n "$GIT" ]; then
    GIT_VERSION=`/usr/bin/git --version | cut -b 13-`
    echo " -> The Git package has already been installed (version $GIT_VERSION)."
  else
    if [ -f "/usr/bin/yum" ]; then
      echo " -> yum --assumeyes install git"
      yum --assumeyes --quiet install git
    elif [ -f "/usr/bin/apt-get" ]; then
      echo " -> apt-get --yes install git"
      apt-get --yes --quiet install git
    elif [ -f "/usr/bin/zypper" ]; then
      echo " -> zypper --yes install git-core"
      zypper --yes --quiet install git-core
    elif [ -f "/usr/bin/emerge" ]; then
      echo " -> emerge dev-vcs/git"
      emerge --quiet dev-vcs/git
    else
      echo "${BOLD}Could not install Git... Please install it before continuing.{$NORMAL}"
      echo
      exit 1
    fi
  fi
}

create_project () {
  if [ -f "/home/storage/$1/HEAD" ]; then
    echo " -> Project \"$1\" already exists."
    echo
  else
    # Create the Git repository
    echo " -> $GIT init --bare /home/storage/$1"
    $GIT init --quiet --bare /home/storage/$1

    # Don't allow force-pushing and data to get lost
    echo " -> $GIT config --file /home/storage/$1/config receive.denyNonFastForwards true"
    $GIT config --file /home/storage/$1/config receive.denyNonFastForwards true
    
    # Set the right permissions
    echo " -> chown --recursive storage:storage /home/storage"
    chown --recursive storage:storage /home/storage

    sleep 0.5

    echo 
    echo "${BOLD}Project \"$1\" was successfully created.${NORMAL}"
  fi

  # Fetch the external IP address
  IP=`curl --silent http://ifconfig.me/ip`
  PORT=`grep --max-count=1 "^Port " /etc/ssh/sshd_config | cut -b 6-`

  # Display info to link with the created project to the user
  echo "To link up a SparkleShare client, enter the following"
  echo "details into the ${BOLD}\"Add Hosted Project...\"${NORMAL} dialog: "
  echo 
  echo "      Address: ${BOLD}storage@$IP:$PORT${NORMAL}"
  echo "  Remote Path: ${BOLD}/home/storage/$1${NORMAL}"
  echo
  echo "To link up (more) computers, use the \"dazzle link\" command."
  echo
}

link_client () {
  # Ask the user for the link code with a prompt
  echo "Paste the contents of ${BOLD}\"~/SparkleShare/Your Name's link code.txt\"${NORMAL}"
  echo "(found on the client) into the field below and press ${BOLD}<ENTER>${NORMAL}."
  echo 
  echo -n "${BOLD}Link code: ${NORMAL}"
  read LINK_CODE
  
  if [ ${#SHELL} > 256 ]; then
    echo $LINK_CODE >> /home/storage/.ssh/authorized_keys
    echo
    echo "${BOLD}The client with this link code can now access projects.${NORMAL}"
    echo "Repeat this step to link more clients."
    echo
  else
    echo "${BOLD}Not a valid link code...${NORMAL}"
  fi
}

show_help () {
    echo "${BOLD}Dazzle, SparkleShare host setup script${NORMAL}"
    echo "This script needs to be run as root"
    echo
    echo "Usage: dazzle [COMMAND]"
    echo 
    echo "  setup                            configures this machine to serve as a SparkleShare host"
    echo "  create PROJECT_NAME              creates a SparkleShare project called PROJECT_NAME"
    echo "  create-encrypted PROJECT_NAME    creates an encrypted SparkleShare project"
    echo "  link                             links a SparkleShare client to this host by entering a link code"
    echo
}


# Parse the command line arguments
case $1 in
  setup)
    echo "${BOLD}(1/4) Creating account \"storage\"...${NORMAL}"
    create_account
    echo "${BOLD}(2/4) Configuring account \"storage\"...${NORMAL}"
    configure_ssh
    echo "${BOLD}(3/4) Restarting the SSH service...${NORMAL}"
    restart_ssh
    echo "${BOLD}(4/4) Installing the Git package...${NORMAL}"
    install_git
    echo
    echo "${BOLD}Setup complete!${NORMAL}"
    echo "To create a new project, run \"dazzle create PROJECT_NAME\"."
    echo
    ;;
  create)    
    echo "${BOLD}Creating project \"$2\"...${NORMAL}"
    create_project $2
    ;;
  create-encrypted)
    echo "${BOLD}Creating encrypted project \"$2\"...${NORMAL}"
    create_project $2-crypto
    ;;
  link)
    link_client $2
    ;;
  *|help)
    show_help
    ;;
esac
