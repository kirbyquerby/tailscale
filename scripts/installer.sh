#!/bin/sh
# Copyright (c) 2021 Tailscale Inc & AUTHORS All rights reserved.
# Use of this source code is governed by a BSD-style
# license that can be found in the LICENSE file.
#
# This script detects the current operating system, and installs
# Tailscale according to that OS's conventions.

set -eu

# All the code is wrapped in a main function that gets called at the
# bottom of the file, so that a truncated partial download doesn't end
# up executing half a script.
main() {
	# Step 1: detect the current linux distro, version, and packaging system.
	#
	# We rely on a combination of 'uname' and /etc/os-release to find
	# an OS name and version, and from there work out what
	# installation method we should be using.
	#
	# The end result of this step is that the following three
	# variables are populated, if detection was successful.
	OS=""
	VERSION=""
	PACKAGETYPE=""
	APT_KEY_TYPE="" # Only for apt-based distros

	if [ -f /etc/os-release ]; then
		# /etc/os-release populates a number of shell variables. We care about the following:
		#  - ID: the short name of the OS (e.g. "debian", "freebsd")
		#  - VERSION_ID: the numeric release version for the OS, if any (e.g. "18.04")
		#  - VERSION_CODENAME: the codename of the OS release, if any (e.g. "buster")
		. /etc/os-release
		case "$ID" in
			ubuntu)
				OS="$ID"
				VERSION="$VERSION_CODENAME"
				PACKAGETYPE="apt"
				# Third-party keyrings became the preferred method of
				# installation in Ubuntu 20.04.
				if expr "$VERSION_ID" : "2.*" >/dev/null; then
					APT_KEY_TYPE="keyring"
				else
					APT_KEY_TYPE="legacy"
				fi
				;;
			debian)
				OS="$ID"
				VERSION="$VERSION_CODENAME"
				PACKAGETYPE="apt"
				# Third-party keyrings became the preferred method of
				# installation in Debian 11 (Bullseye).
				if [ "$VERSION_ID" -lt 11 ]; then
					APT_KEY_TYPE="legacy"
				else
					APT_KEY_TYPE="keyring"
				fi
				;;
			raspbian)
				OS="$ID"
				VERSION="$VERSION_CODENAME"
				PACKAGETYPE="apt"
				# Third-party keyrings became the preferred method of
				# installation in Raspbian 11 (Bullseye).
				if [ "$VERSION_ID" -lt 11 ]; then
					APT_KEY_TYPE="legacy"
				else
					APT_KEY_TYPE="keyring"
				fi
				;;
			centos)
				OS="$ID"
				VERSION="$VERSION_ID"
				PACKAGETYPE="dnf"
				if [ "$VERSION" = "7" ]; then
					PACKAGETYPE="yum"
				fi
				;;
			ol)
				OS="oracle"
				VERSION="$(echo "$VERSION_ID" | cut -f1 -d.)"
				PACKAGETYPE="dnf"
				if [ "$VERSION" = "7" ]; then
					PACKAGETYPE="yum"
				fi
				;;
			rhel)
				OS="$ID"
				VERSION="$(echo "$VERSION_ID" | cut -f1 -d.)"
				PACKAGETYPE="dnf"
				;;
			fedora)
				OS="$ID"
				VERSION=""
				PACKAGETYPE="dnf"
				;;
			amzn)
				OS="amazon-linux"
				VERSION="$VERSION_ID"
				PACKAGETYPE="yum"
				;;
			opensuse-leap)
				OS="opensuse"
				VERSION="leap/$VERSION_ID"
				PACKAGETYPE="zypper"
				;;
			opensuse-tumbleweed)
				OS="opensuse"
				VERSION="tumbleweed"
				PACKAGETYPE="zypper"
				;;
 			arch)
				OS="$ID"
				VERSION="" # rolling release
				PACKAGETYPE="pacman"
				;;
			manjaro)
				OS="$ID"
				VERSION="" # rolling release
				PACKAGETYPE="pacman"
				;;
			alpine)
				OS="$ID"
				VERSION="$VERSION_ID"
				PACKAGETYPE="apk"
				;;
			nixos)
				echo "Please add Tailscale to your NixOS configuration directly:"
				echo
				echo "services.tailscale.enable = true;"
				exit 1
				;;
			void)
				OS="$ID"
				VERSION="" # rolling release
				PACKAGETYPE="xbps"
				;;
			gentoo)
				OS="$ID"
				VERSION="" # rolling release
				PACKAGETYPE="emerge"
				;;
			freebsd)
				OS="$ID"
				VERSION="$(echo "$VERSION_ID" | cut -f1 -d.)"
				PACKAGETYPE="pkg"
				;;
			# TODO: wsl?
			# TODO: synology? qnap?
		esac
	fi

	# If we failed to detect something through os-release, consult
	# uname and try to infer things from that.
	if [ -z "$OS" ]; then
		if type uname >/dev/null 2>&1; then
			case "$(uname)" in
				FreeBSD)
					# FreeBSD before 12.2 doesn't have
					# /etc/os-release, so we wouldn't have found it in
					# the os-release probing above.
					OS="freebsd"
					VERSION="$(freebsd-version | cut -f1 -d.)"
					PACKAGETYPE="pkg"
					;;
				OpenBSD)
					OS="openbsd"
					VERSION="$(uname -r)"
					PACKAGETYPE=""
					;;
				Darwin)
					OS="macos"
					VERSION="$(sw_vers -productVersion | cut -f1-2 -d.)"
					PACKAGETYPE="appstore"
					;;
				Linux)
					OS="other-linux"
					VERSION=""
					PACKAGETYPE=""
					;;
			esac
		fi
	fi

	# Step 2: having detected an OS we support, is it one of the
	# versions we support?
	OS_UNSUPPORTED=
	case "$OS" in
		ubuntu)
			if [ "$VERSION" != "xenial" ] && \
			   [ "$VERSION" != "bionic" ] && \
			   [ "$VERSION" != "eoan" ] && \
			   [ "$VERSION" != "focal" ] && \
			   [ "$VERSION" != "groovy" ] && \
			   [ "$VERSION" != "hirsute" ] && \
			   [ "$VERSION" != "impish" ]
			then
				OS_UNSUPPORTED=1
			fi
		;;
		debian)
			if [ "$VERSION" != "stretch" ] && \
			   [ "$VERSION" != "buster" ] && \
			   [ "$VERSION" != "bullseye" ] && \
			   [ "$VERSION" != "bookworm" ] && \
			   [ "$VERSION" != "sid" ]
			then
				OS_UNSUPPORTED=1
			fi
		;;
		raspbian)
			if [ "$VERSION" != "buster" ] && \
			   [ "$VERSION" != "bullseye" ]
			then
				OS_UNSUPPORTED=1
			fi
		;;
		centos)
			if [ "$VERSION" != "7" ] && \
			   [ "$VERSION" != "8" ]
			then
				OS_UNSUPPORTED=1
			fi
		;;
		oracle)
			if [ "$VERSION" != "7" ] && \
			   [ "$VERSION" != "8" ]
			then
				OS_UNSUPPORTED=1
			fi
		;;
		rhel)
			if [ "$VERSION" != "8" ]
			then
				OS_UNSUPPORTED=1
			fi
		;;
		amazon-linux)
			if [ "$VERSION" != "2" ]
			then
				OS_UNSUPPORTED=1
			fi
		;;
		opensuse)
			if [ "$VERSION" != "leap/15.1" ] && \
			   [ "$VERSION" != "leap/15.2" ] && \
			   [ "$VERSION" != "leap/15.3" ] && \
			   [ "$VERSION" != "tumbleweed" ]
			then
				OS_UNSUPPORTED=1
			fi
			;;
		arch)
			# Rolling release, no version checking needed.
			;;
		manjaro)
			# Rolling release, no version checking needed.
			;;
		alpine)
			# All versions supported, no version checking needed.
			# TODO: is that true? When was tailscale packaged?
			;;
		void)
			# Rolling release, no version checking needed.
			;;
		gentoo)
			# Rolling release, no version checking needed.
			;;
		freebsd)
			if [ "$VERSION" != "12" ] && \
			   [ "$VERSION" != "13" ]
			then
				OS_UNSUPPORTED=1
			fi
			;;
		openbsd)
			OS_UNSUPPORTED=1
			;;
		macos)
			# We delegate macOS installation to the app store, it will
			# perform version checks for us.
			;;
		other-linux)
			OS_UNSUPPORTED=1
			;;
		*)
			OS_UNSUPPORTED=1
			;;
	esac
	if [ "$OS_UNSUPPORTED" = "1" ]; then
		case "$OS" in
			other-linux)
				echo "Couldn't determine what kind of Linux is running."
				echo "You could try the static binaries at:"
				echo "https://pkgs.tailscale.com/stable/#static"
				;;
			"")
				echo "Couldn't determine what operating system you're running."
				;;
			*)
				echo "$OS $VERSION isn't supported by this script yet."
				;;
		esac
		echo
		echo "If you'd like us to support your system better, please email support@tailscale.com"
		echo "and tell us what OS you're running."
		echo
		echo "Please include the following information we gathered from your system:"
		echo
		echo "OS=$OS"
		echo "VERSION=$VERSION"
		echo "PACKAGETYPE=$PACKAGETYPE"
		if type uname >/dev/null 2>&1; then
			echo "UNAME=$(uname -a)"
		else
			echo "UNAME="
		fi
		echo
		if [ -f /etc/os-release ]; then
			cat /etc/os-release
		else
			echo "No /etc/os-release"
		fi
		exit 1
	fi

	# Step 3: work out if we can run privileged commands, and if so,
	# how.
	CAN_ROOT=
	SUDO=
	if [ "$(id -u)" = 0 ]; then
		CAN_ROOT=1
		SUDO=""
	elif type sudo >/dev/null; then
		CAN_ROOT=1
		SUDO="sudo"
	elif type doas >/dev/null; then
		CAN_ROOT=1
		SUDO="doas"
	fi
	if [ "$CAN_ROOT" != "1" ]; then
		echo "This installer needs to run commands as root."
		echo "We tried looking for 'sudo' and 'doas', but couldn't find them."
		echo "Either re-run this script as root, or set up sudo/doas."
		exit 1
	fi


	# Step 4: run the installation.
	echo "Installing Tailscale for $OS $VERSION, using method $PACKAGETYPE"
	case "$PACKAGETYPE" in
		apt)
			# Ideally we want to use curl, but on some installs we
			# only have wget. Detect and use what's available.
			CURL=
			if type curl >/dev/null; then
				CURL="curl -fsSL"
			elif type wget >/dev/null; then
				CURL="wget -q -O-"
			fi
			if [ -z "$CURL" ]; then
				echo "The installer needs either curl or wget to download files."
				echo "Please install either curl or wget to proceed."
				exit 1
			fi
			if ! type gpg >/dev/null; then
				echo "The installer needs gnupg to do keyring management."
				echo "Please install gnupg to proceed".
				exit 1
			fi

			set -x
			$SUDO mkdir -p --mode=0755 /usr/share/keyrings
			case "$APT_KEY_TYPE" in
				legacy)
					$CURL "https://pkgs.tailscale.com/stable/$OS/$VERSION.asc" | $SUDO apt-key add -
					$CURL "https://pkgs.tailscale.com/stable/$OS/$VERSION.list" | $SUDO tee /etc/apt/sources.list.d/tailscale.list
				;;
				keyring)
					$CURL "https://pkgs.tailscale.com/stable/$OS/$VERSION.noarmor.gpg" | $SUDO tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null
					$CURL "https://pkgs.tailscale.com/stable/$OS/$VERSION.tailscale-keyring.list" | $SUDO tee /etc/apt/sources.list.d/tailscale.list
				;;
			esac
			$SUDO apt-get update
			$SUDO apt-get install tailscale
			set +x
		;;
		yum)
			set -x
			$SUDO yum install yum-utils
			$SUDO yum-config-manager --add-repo "https://pkgs.tailscale.com/stable/$OS/$VERSION/tailscale.repo"
			$SUDO yum install tailscale
			$SUDO systemctl enable --now tailscaled
			set +x
		;;
		dnf)
			set -x
			$SUDO dnf config-manager --add-repo "https://pkgs.tailscale.com/stable/$OS/$VERSION/tailscale.repo"
			$SUDO dnf install tailscale
			$SUDO systemctl enable --now tailscaled
			set +x
		;;
		zypper)
			set -x
			$SUDO zypper ar -g -r "https://pkgs.tailscale.com/stable/$OS/$VERSION/tailscale.repo"
			$SUDO zypper ref
			$SUDO zypper in tailscale
			$SUDO systemctl enable --now tailscaled
			set +x
			;;
		pacman)
			set -x
			$SUDO pacman -S tailscale
			$SUDO systemctl enable --now tailscaled
			set +x
			;;
		apk)
			set -x
			$SUDO apk add tailscale
			$SUDO rc-update add tailscale
			set +x
			;;
		xbps)
			set -x
			$SUDO xbps-install tailscale
			set +x
			;;
		emerge)
			set -x
			$SUDO emerge net-vpn/tailscale
			set +x
			;;
		appstore)
			set -x
			open "https://apps.apple.com/us/app/tailscale/id1475387142"
			set +x
			;;
		*)
			echo "unexpected: unknown package type $PACKAGETYPE"
			exit 1
			;;
	esac

	echo "Installation complete! Log in to start using Tailscale by running:"
	echo
	if [ -z "$SUDO" ]; then
		echo "tailscale up"
	else
		echo "$SUDO tailscale up"
	fi
}

main
