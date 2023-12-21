#!/usr/bin/env bash

# Color constants used for printing messages in color.
YELLOW='\033[0;33m'       # Yellow
NC='\033[0m' 		  # No Color
GREEN='\033[0;32m'        # Green

# Variables used in the script
virtual_env_name="virtual_env_dependencies"
no_caching=false
color=false
filename="requirements.txt"

# Print the below help message
function usage() {
	# cat << EOF prints out text and stops printing the moment it matches the text found after '<<'
	cat << ENDMSG
Usage:
./setup [-e|-ename|--ename <virtual environment name>] [-n|-nocache|--nocache] [-c|-color|--color] [-h|-help|--help]
OR
source setup [-e|-ename|--ename <virtual environment name>] [-n|-nocache|--nocache] [-c|-color|--color]
# DO NOT send the -h flag when running source with this script. Your terminal session will close immediately.

Description:
This script the setup for the virtual envirnoment to install all dependencies in an isolated environment.
The script first looks for the recommended virtual environment directory (which can be specified as a command line argument),
and if it exists, it compares the dependencies installed with the dependencies in the requirements.txt file. If the dependencies
are not matching, all existing dependencies are uninstalled and the dependencies specified in requirements.txt are installed instead.

************************************************************IMPORTANT****************************************************************

YOU MUST HAVE A requirements.txt FILE THAT CONTAINS THE OUTPUT OF "pip freeze" IN YOUR DIRECTORY. OTHERWISE THIS SCRIPT WILL THROW
UNEXPECTED ERRORS. THEY MAY CHANGE YOUR LOCAL ENVIRONMENT. THIS IS A FAIR WARNING.

*************************************************************************************************************************************

*******************************************************Important suggestion**********************************************************

It is recommended to run the second version (source setup) to so that the virtual environment is loaded
into your terminal, and you can run the script from there. Otherwise you have to run the command below (for git bash at least).
source ./\${DIRNAME}/Scripts/activate

*************************************************************************************************************************************

Arguments supported:
-h	-help		--help		Display this help message and exit immediately if this is specified.

-e	-ename		--ename		Specify the virtual environment directory name. By default this is "virtual_env_dependencies".

-n	-nocache	--nocache	Does not use cached packages when managing dependencies. This installs packages with the --no-cache-dir
					flag, and purges the cache with "pip cache purge" when uninstalling dependencies. This will upgrade pip
					with the --no-cache-dir flag as well. If you specify this, then the script will take more time and cause
					significantly more network usage.

-c	-color		--color		Print color messages. Print messages in yellow or green (yellow means some adjustment is being made,
					green means the packages have all been installed successfully). This is disabled by default.

-f	-filename	--filename	Specify the filename that has the listed dependencies you install. This filename should be the output
					of "pip freeze". By default it is "requirements.txt".

Examples:
./setup -h 					# Prints this help message
./setup -ename=dirname 				# sets virtual environment directory name to be "dirname"
./setup --ename=dirname				# same as above
./setup -e dirname				# same as above
./setup -n					# disable caching
./setup -nocache				# disable caching
./setup --nocache				# disable caching
./setup --color					# print color messages
./setup -color					# print color messages
./setup -c					# print color messages
./setup -c --nocache --ename=dependencies	# disable caching, sets the virtual environment directory name to be "dependencies", and enables color messaging
./setup						# sets the virtual environment directory to be the default: "virtual_env_dependencies" (and continues from there)
ENDMSG
}

# Print text in color. One argument is allowed, which is the color code.
# The text you want to change in color should be passed in as input to this function
# (i.e. through redirection - e.g. 'echo "Hello World" | print_color "${GREEN}"')
function print_color() {
	if [ ${#} -eq 1 ]
	then
		echo -en "${1}"
	else
		echo -en "${NC}"
	fi
	if [ "${color}" = false ]
	then
		echo -en "${NC}"
	fi
	cat -
	echo -en "${NC}"
}

# Some users have "python" pointing directly to python3, and they don't actually have python3 as a command on their machine.
# Other users have "python3" pointing to python3 as a command, but not "python" as a command (or if python is installed, it
# points to python2, which will not work).
function use_correct_python_version() {
	python_version=0
	/usr/bin/env python --version &> /dev/null
	if [[ ${?} -eq 0 ]]
	then
		python_version=$(/usr/bin/env python --version 2> /dev/null | awk '{ print $NF }' 2> /dev/null | awk -F . '{ print $1 }' 2> /dev/null)
		if [[ ${python_version} -eq 3 ]]
		then
			/usr/bin/env python "${@}"
		else
			/usr/bin/env python3 --version &> /dev/null
			if [[ ${?} -eq 0 ]]
			then
				/usr/bin/env python3 "${@}"
			else
				echo "Python not installed." &>2
				exit 2
			fi
		fi
	else
		/usr/bin/env python3 --version &> /dev/null
		if [[ ${?} -eq 0 ]]
		then
			/usr/bin/env python3 "${@}"
		else
			echo "Python not installed." &>2
		fi
	fi
}

# Upgrade pip when an upgrade is available, --no-cache-dir is run to disable caching if that argument is specified
function upgrade_pip() {
	if [ "${1}" = true ]
	then
		use_correct_python_version -m pip install --upgrade pip --quiet --no-cache-dir
	else
		use_correct_python_version -m pip install --upgrade pip --quiet
	fi
}

# Install dependencies with pip install. --no-cache-dir is run to disable caching if that argument is specified
function install_dependencies() {
	if [ "${1}" = true ]
	then
		use_correct_python_version -m pip install -r ${filename} --quiet --no-cache-dir
	else
		use_correct_python_version -m pip install -r ${filename} --quiet
	fi
}

# The part of the script that parses arguments passed into the command line. The script uses getopt,
# so you should try checking to see if getopt is available in your terminal by typing 'getopt --help'.
if [ ${#} -ne 0 ]
then
	options=$(getopt -l "help,nocache,color,ename:" -o "hnce:" -a -- "${@}")
	if [ ${?} -ne 0 ]
	then
		echo "Incorrect invocation of the script. Printing help message below and exiting with an error code of 1."
		usage
		exit 1
	fi
	eval set -- "${options}"
	while true
	do
	case "${1}" in
		-h|--help)
			usage
			exit 0
			break
			;;
		-e|--ename)
			shift
			virtual_env_name="${1}"
			;;
		-f|--filename)
			shift
			filename="${1}"
			if [ ! -f "${filename}" ]
			then
				echo "${filename} does not exist. Using \"requirements.txt\"" | print_color "${YELLOW}"
				filename="requirements.txt"
			fi
			;;
		-n|--nocache)
			no_caching=true
			;;
		-c|--color)
			color=true
			;;
		--)
			shift
			break
			;;

	esac
	shift
	done
fi

tempfile=$(mktemp)
diff_output=$(mktemp)
# Use the find command to search for the directory with the virtual environment directory name. Use the length of the directories matching to
# determine if the directory exists.
directories_matching=$(find ./ -type d -name "${virtual_env_name}")
length=$(echo ${directories_matching} | wc -c)
if [ ${length} -gt 1 ]
then
	# Directory was found, so try activating the script to start the virtual environment. If it doesn't work (non-zero return code), then
	# remove this directory and install a new virtual environment with the same directory name. If it works, then check the existing package
	# dependencies.
	source ./${virtual_env_name}/Scripts/activate 2> /dev/null
	if [ ${?} -ne 0 ]
	then
		echo "Existing \"${virtual_env_name}\" directory found that is not a virtual environment directory." | print_color "${YELLOW}"
		echo "This script will delete it, install a new virtual environment with directory name \"${virtual_env_name}\", and install dependencies." | print_color "${YELLOW}"
		rm -r "./${virtual_env_name}"
		use_correct_python_version -m venv "./${virtual_env_name}"
		source ./${virtual_env_name}/Scripts/activate
		upgrade_pip "${no_caching}"
		install_dependencies "${no_caching}"
		echo "Requirements have been installed." | print_color "${GREEN}"
	else
		# Check the current package dependency listing and compare it with requirements.txt using the diff command to determine if there
		# are any differences in package installed (i.e. different version, different packages installed, etc.)
		use_correct_python_version -m pip freeze > ${tempfile}
		diff ${tempfile} ./requirements.txt -ZEbB > ${diff_output}
		lines_difference=$(wc -l ${diff_output} | awk '{ print $1 }')
		if [ ${lines_difference} -gt 0 ]
		then
			echo "Existing package installations were found that differ from the dependencies in ${filename}" | print_color "${YELLOW}"
			echo "Removing all existing dependencies and installing the dependencies in ${filename}" | print_color "${YELLOW}"
			upgrade_pip "${no_caching}"
			use_correct_python_version -m pip uninstall -r ${tempfile} -y --quiet
			if [ "${no_caching}" = true ]
			then
				use_correct_python_version -m pip cache purge 2> /dev/null
			fi
			install_dependencies "${no_caching}"
			echo "Requirements have been installed." | print_color "${GREEN}"
		fi
		upgrade_pip "${no_caching}"
	fi
else
	# If the length variable is 0, then there is no existing directory with the given virtual environment name. Create a virtual environment
	# with this directory name and install all of the dependencies.
	echo "No existing virtual environment found with directory name \"${virtual_env_name}\"." | print_color "${YELLOW}"
	echo "Creating a new virtual environment with directory name \"${virtual_env_name}\" and installing the dependencies listed in ${filename}" | print_color "${YELLOW}"
	use_correct_python_version -m venv "./${virtual_env_name}"
	source ./${virtual_env_name}/Scripts/activate
	upgrade_pip "${no_caching}"
	install_dependencies "${no_caching}"
	echo "Requirements have been installed." | print_color "${GREEN}"
fi

# Remove the tempfiles we create
rm ${tempfile}
rm ${diff_output}
