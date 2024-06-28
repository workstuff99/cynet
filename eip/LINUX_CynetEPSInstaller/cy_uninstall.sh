#!/bin/bash

if [ $(id -u) != 0 ]; then
    echo "[ERROR] Uninstaller must be run as root (or with sudo), please run uninstaller as root"
    exit 1
fi

if [ -f /etc/debian_version ]; then
	HAS_DEB=true
elif [ -f /etc/system-release-cpe ]; then
	HAS_RPM=true
elif command -v rpm >/dev/null 2>&1 && ! command -v apt >/dev/null 2>&1; then
	HAS_RPM=true
else
	echo "Unsupported distro. Exiting!"
	exit 1
fi

#set -x
if [ ! -z $HAS_DEB ]; then
	echo "Check if proccess if there is dpkg lock."
	if [ -x "$(command -v lsof)" ]; then
		echo "Unlock /var/lib/dpkg/lock"
		if [ -f /var/lib/dpkg/lock ]; then
			lsof /var/lib/dpkg/lock
		fi
		echo "Unlock /var/lib/dpkg/lock-frontend"
		if [ -f /var/lib/dpkg/lock-frontend ]; then
			lsof /var/lib/dpkg/lock-frontend
		fi
	fi
fi

echo "Trying to remove package if installed"
ServiceRemoveSucceed=false
ForceKill=true
if [ ! -z $HAS_DEB ]; then
	echo "Command dpkg found"
	dpkg --list cyneteps
	RET_VAL=$?
	echo "Return value of dpkg list: " $RET_VAL
	if [ $RET_VAL -eq 0 ]; then
		echo "Purging deb package"
		ForceKill=false
		dpkg --purge --force-all cyneteps
		if [ $? -ne 0 ]; then
			echo "Erasing deb failed - try apocaliptic step"
			rm /var/lib/dpkg/info/cyneteps.*
			echo "Purging deb package again"
			dpkg --purge --force-all cyneteps
		else
			dpkg --configure -a
			ServiceRemoveSucceed=true
		fi
	fi
elif [ ! -z $HAS_RPM ]; then
	rpm -qa | grep -i CynetEPS
	RET_VAL=$?
	echo "Return value of rpm -qa: " $RET_VAL
	if [ $RET_VAL -eq 0 ]; then
		echo "Removing RPM package"
		ForceKill=false
		rpm -e CynetEPS
		if [ $? -ne 0 ]; then
			echo "Erasing RPM failed - try apocaliptic step"
			rpm -e CynetEPS --noscripts
			#rpm -e --allmatches CynetEPS
		else
			ServiceRemoveSucceed=true
		fi
	fi
fi

echo "Trying to remove manual installation"
echo "Checking for existing service"

if [ "$ServiceRemoveSucceed" = false ]; then
	if [ -x "$(command -v systemctl)" ]; then
		echo "stopping service if running using systemctl"
		if [ "$(systemctl is-enabled  cyuninstalleps.service)" = "enabled" ]
					then
			ERRORMESS=$( systemctl daemon-reexec )
			echo daemon-reexec error message: $ERRORMESS
			systemctl stop  cyuninstalleps.service
			systemctl disable  cyuninstalleps.service
			systemctl daemon-reload
			systemctl reset-failed
			rm /lib/systemd/system/cyuninstalleps.service
			rm /tmp/uninstallscrip.sh
		fi
		if [ "$(systemctl is-enabled cyservice)" = "enabled" ]
				then
			systemctl stop cyservice
			echo "removing existing service using systemctl"
			ERRORMESS=$( systemctl daemon-reexec )
			echo daemon-reexec error message: $ERRORMESS
			systemctl disable cyservice
			systemctl daemon-reload
			systemctl reset-failed
			ServiceRemoveSucceed=true
		fi
	fi
fi

if [ "$ServiceRemoveSucceed" = false ]; then
	if [ -x "$(command -v chkconfig)" ]; then
		chkconfig --list cyservice
		if [ $? -eq 0 ]; then
			echo "removing existing service using chkconfig"
			service cyservice stop
			chkconfig cyservice off
			chkconfig --del cyservice
			yes | rm -f /etc/init.d/cyservice
			yes | rm -f /etc/rc.d/init.d/cyservice
			ServiceRemoveSucceed=true
		fi
	fi
fi

if [ "$ServiceRemoveSucceed" = false ]; then
	if [ -x "$(command -v update-rc.d)" ]; then
		echo "removing service if running using update-rc.d"
		echo "removing existing service using update-rc"
		if [ -f /etc/init.d/cyservice ]; then
			update-rc.d cyservice disable
			yes | rm /etc/init.d/cyservice
			update-rc.d -f cyservice remove
		fi
	fi
fi

if [ "$ServiceRemoveSucceed" = false ] || [ "$ForceKill" = true ] ; then
    echo "Service is not installed or we try to uninstall not packages EPS version"
    echo "  try to terminate CynetEPS, if running"
    pkill -9 CynetEPS
    echo "  try to terminate avupdate.bin, if running"
	pkill -9 avupdate.bin
    echo "  try to terminate CynetAV, if running"
	pkill -9 CynetAV

	if [ -x "$(command -v lsof)" ]; then
	 	echo "Unlock /opt/Cynet/AV/CynetAV.sock.lock"
	 	if [ -f "/opt/Cynet/AV/CynetAV.sock.lock" ]; then
	 		echo "Unlocking /opt/Cynet/AV/CynetAV.sock.lock"
	 		lsof /opt/Cynet/AV/CynetAV.sock.lock
	 	fi
	fi

	echo   "Removing CynetEPS audit rules if needed."
	if [ -f "/etc/audit/rules.d/CynetAu.rules" ]; then
		echo "removing audit rules file /etc/audit/rules.d/CynetAu.rules"
		rm -f "/etc/audit/rules.d/CynetAu.rules"
	else 
		echo "No Cynet audit rules configured."
	fi

	if [ -x "$(command -v auditctl)" ]; then
		echo "Run auditctl to remove rules with cynetaukey key."
		auditctl -D -k cynetaukey
	fi

	# leave for possibility is some beta was installed in computer from deprecated plugin functionality to avoid junk
	echo   "Removing CynetEPS audit plugin if needed."
	restart_AuditD=false
	if [ -f "/etc/audit/plugins.d/CynetAu.conf" ]; then
		echo "removing plugin file /etc/audit/plugins.d/CynetAu.conf"
		rm -f "/etc/audit/plugins.d/CynetAu.conf"
		restart_AuditD=true
	fi
	if [ -f "/etc/audisp/plugins.d/CynetAu.conf" ]; then
		echo "removing plugin file /etc/audisp/plugins.d/CynetAu.conf"
		rm -f "/etc/audisp/plugins.d/CynetAu.conf"
		restart_AuditD=true
	fi

	#we do not use systemctl because in part of rh, it will refuse to restart auditd by strange error, the suggestion to workaround it by service util.!!!!
	if [ "$restart_AuditD" = true ]; then
		service auditd status >> /dev/null
		if [ $? -ne 0 ]; then
			echo "auditd stopped or disabled, no need to restart it to unregister cynet audit plugin"
		else 
			echo "restart auditd, to unregister cynet audit plugin"
			service auditd restart
		fi 
	else
		echo "No Cynet Audit plugin installed."
	fi	
fi

echo "Removing /opt/Cynet"
rm -fRd "/opt/Cynet"

if [ -f "/usr/lib/systemd/system/cyservice.service" ]; then
	echo "Removing /usr/lib/systemd/system/cyservice.service"
	rm -f "/usr/lib/systemd/system/cyservice.service"
fi

if [ -f "/lib/systemd/system/cyservice.service" ]; then
	echo "Removing /lib/systemd/system/cyservice.service"
	rm -f "/lib/systemd/system/cyservice.service"
fi

if [ -f "/tmp/CynetEPSArguments.txt" ]; then
	echo "Removing /tmp/CynetEPSArguments.txt"
	rm -f "/tmp/CynetEPSArguments.txt"
fi

exit 0
