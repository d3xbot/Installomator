#!/bin/sh

# Installation using Installomator with Dialog showing progress (and posibility of adding to the Dock)
# Installation of software using `valuesfromarguments` to install a custom software using Installomator through GitHub

LOGO="mosyleb" # "mosyleb", "mosylem", "addigy", "microsoft", "ws1"

#item="gfxcardstatus" # enter the software to install (if it has a label in future version of Installomator)

# Label variables below

# GitHub functions
downloadURLFromGit() { # $1 git user name, $2 git repo name
    gitusername=${1?:"no git user name"}
    gitreponame=${2?:"no git repo name"}

    if [[ $type == "pkgInDmg" ]]; then
        filetype="dmg"
    elif [[ $type == "pkgInZip" ]]; then
        filetype="zip"
    else
        filetype=$type
    fi

    if [ -n "$archiveName" ]; then
        downloadURL=https://github.com$(curl -sfL "https://github.com/$gitusername/$gitreponame/releases/latest" | tr '"' "\n" | grep -i "^/.*\/releases\/download\/.*$archiveName" | head -1 || true)
        if [[ "$(echo $downloadURL | grep -ioE "https.*$archiveName" || true)" == "" ]]; then
            #printlog "Trying GitHub API for download URL."
            downloadURL=$(curl -sfL "https://api.github.com/repos/$gitusername/$gitreponame/releases/latest" | awk -F '"' "/browser_download_url/ && /$archiveName\"/ { print \$4; exit }" || true)
        fi
    else
        downloadURL=https://github.com$(curl -sfL "https://github.com/$gitusername/$gitreponame/releases/latest" | tr '"' "\n" | grep -i "^/.*\/releases\/download\/.*\.$filetype" | head -1 || true)
        if [[ "$(echo $downloadURL | grep -ioE "https.*.$filetype" || true)" == "" ]]; then
            #printlog "Trying GitHub API for download URL."
            downloadURL=$(curl -sfL "https://api.github.com/repos/$gitusername/$gitreponame/releases/latest" | awk -F '"' "/browser_download_url/ && /$filetype\"/ { print \$4; exit }" || true)
        fi
    fi
    if [ -z "$downloadURL" ]; then
        echo "could not retrieve download URL for $gitusername/$gitreponame"
        exit 1
    else
        echo "$downloadURL"
        return 0
    fi
}
versionFromGit() {
    # credit: Søren Theilgaard (@theilgaard)
    # $1 git user name, $2 git repo name
    gitusername=${1?:"no git user name"}
    gitreponame=${2?:"no git repo name"}

    #appNewVersion=$(curl -L --silent --fail "https://api.github.com/repos/$gitusername/$gitreponame/releases/latest" | grep tag_name | cut -d '"' -f 4 | sed 's/[^0-9\.]//g' || true)
    appNewVersion=$(curl -sLI "https://github.com/$gitusername/$gitreponame/releases/latest" | grep -i "^location" | tr "/" "\n" | tail -1 | sed 's/[^0-9\.]//g' || true)
    if [ -z "$appNewVersion" ]; then
        #echo "could not retrieve version number for $gitusername/$gitreponame"
        appNewVersion=""
    else
        echo "$appNewVersion"
        return 0
    fi
}

# Variables for label
name="gfxCardStatus"
type="zip"
downloadURL="$(downloadURLFromGit codykrieger gfxCardStatus)"
appNewVersion="$(versionFromGit codykrieger gfxCardStatus)"
expectedTeamID="LF22FTQC25"

# Dialog icon
icon=""
# icon should be a file system path or an URL to an online PNG.
# In Mosyle an URL can be found by copy picture address from a Custom Command icon.

# dockutil variables
addToDock="1" # with dockutil after installation (0 if not)
appPath="/Applications/$name.app"

# Other variables
dialog_command_file="/var/tmp/dialog.log"
dialogApp="/Library/Application Support/Dialog/Dialog.app"
dockutil="/usr/local/bin/dockutil"

installomatorOptions="BLOCKING_PROCESS_ACTION=prompt_user NOTIFY=silent DIALOG_CMD_FILE=${dialog_command_file}" # Separated by space

# Other installomatorOptions:
#   LOGGING=REQ
#   LOGGING=DEBUG
#   LOGGING=WARN
#   BLOCKING_PROCESS_ACTION=ignore
#   BLOCKING_PROCESS_ACTION=tell_user
#   BLOCKING_PROCESS_ACTION=tell_user_then_quit
#   BLOCKING_PROCESS_ACTION=prompt_user
#   BLOCKING_PROCESS_ACTION=prompt_user_loop
#   BLOCKING_PROCESS_ACTION=prompt_user_then_kill
#   BLOCKING_PROCESS_ACTION=quit
#   BLOCKING_PROCESS_ACTION=kill
#   NOTIFY=all
#   NOTIFY=success
#   NOTIFY=silent
#   IGNORE_APP_STORE_APPS=yes
#   INSTALL=force
######################################################################
# To be used as a script sent out from a MDM.
# Fill the variable "item" above with a label.
# Script will run this label through Installomator.
######################################################################
# v. 10.1 : github-functions added. Improved appIcon handling. Can add the app to Dock using dockutil.
# v. 10   : Integration with Dialog and Installomator v. 10
# v.  9.3 : Better logging handling and installomatorOptions fix.
######################################################################

# Mark: Script
# PATH declaration
export PATH=/usr/bin:/bin:/usr/sbin:/sbin

echo "$(date +%F\ %T) [LOG-BEGIN] $item"

dialogUpdate() {
    # $1: dialog command
    local dcommand="$1"

    if [[ -n $dialog_command_file ]]; then
        echo "$dcommand" >> "$dialog_command_file"
        echo "Dialog: $dcommand"
    fi
}
checkCmdOutput () {
    # $1: cmdOutput
    local cmdOutput="$1"
    exitStatus="$( echo "${cmdOutput}" | grep --binary-files=text -i "exit" | tail -1 | sed -E 's/.*exit code ([0-9]).*/\1/g' || true )"
    if [[ ${exitStatus} -eq 0 ]] ; then
        echo "${item} succesfully installed."
        warnOutput="$( echo "${cmdOutput}" | grep --binary-files=text -i "warn" || true )"
        echo "$warnOutput"
    else
        echo "ERROR installing ${item}. Exit code ${exitStatus}"
        echo "$cmdOutput"
        #errorOutput="$( echo "${cmdOutput}" | grep --binary-files=text -i "error" || true )"
        #echo "$errorOutput"
    fi
}

# Check the currently logged in user
currentUser=$(stat -f "%Su" /dev/console)
if [ -z "$currentUser" ] || [ "$currentUser" = "loginwindow" ] || [ "$currentUser" = "_mbsetupuser" ] || [ "$currentUser" = "root" ]; then
    echo "ERROR. Logged in user is $currentUser! Cannot proceed."
    exit 97
fi
# Get the current user's UID for dockutil
uid=$(id -u "$currentUser")
# Find the home folder of the user
userHome="$(dscl . -read /users/${currentUser} NFSHomeDirectory | awk '{print $2}')"

# Verify that Installomator has been installed
destFile="/usr/local/Installomator/Installomator.sh"
if [ ! -e "${destFile}" ]; then
    echo "Installomator not found here:"
    echo "${destFile}"
    echo "Exiting."
    exit 99
fi

# No sleeping
/usr/bin/caffeinate -d -i -m -u &
caffeinatepid=$!
caffexit () {
    kill "$caffeinatepid"
    pkill caffeinate
    exit $1
}

# Mark: Installation begins
installomatorVersion="$(${destFile} version | cut -d "." -f1 || true)"

if [[ $installomatorVersion -lt 10 ]] || [[ $(sw_vers -buildVersion) < "20A" ]]; then
    echo "Installomator should be at least version 10 to support Dialog. Installed version $installomatorVersion."
    echo "And macOS 11 Big Sur (build 20A) is required for Dialog. Installed build $(sw_vers -buildVersion)."
    installomatorNotify="NOTIFY=all"
else
    installomatorNotify=""
    # check for Swift Dialog
    if [[ ! -d $dialogApp ]]; then
        echo "Cannot find dialog at $dialogApp"
        # Install using Installlomator
        cmdOutput="$(${destFile} dialog LOGO=$LOGO BLOCKING_PROCESS_ACTION=ignore LOGGING=REQ NOTIFY=silent || true)"
        checkCmdOutput $cmdOutput
    fi

    # Configure and display swiftDialog
    #itemName=$( ${destFile} ${item} RETURN_LABEL_NAME=1 LOGGING=REQ INSTALL=force | tail -1 || true )
    itemName="$name"
    if [[ "$itemName" != "#" ]]; then
        message="Installing ${itemName}…"
    else
        message="Installing ${item}…"
    fi
    echo "$item $itemName"
    
    # If no icon defined we are trying to search for installed app icon
    if [[ "$icon" == "" ]]; then
        appPath=$(mdfind "kind:application AND name:$itemName" | head -1 || true)
        appIcon=$(defaults read "${appPath}/Contents/Info.plist" CFBundleIconFile || true)
        if [[ "$(echo "$appIcon" | grep -io ".icns")" == "" ]]; then
            appIcon="${appIcon}.icns"
        fi
        icon="${appPath}/Contents/Resources/${appIcon}"
        echo "${icon}"
        if [ ! -f "${icon}" ]; then
            icon="/System/Applications/App Store.app/Contents/Resources/AppIcon.icns"
        fi
    fi
    echo "${icon}"

    # display first screen
    open -a "$dialogApp" --args \
        --title none \
        --icon "$icon" \
        --message "$message" \
        --mini \
        --progress 100 \
        --position bottomright \
        --movable \
        --commandfile "$dialog_command_file"

    # give everything a moment to catch up
    sleep 0.1
fi

# Install software using Installomator with valuesfromarguments
cmdOutput="$(${destFile} valuesfromarguments LOGO=$LOGO \
    name=${name} \
    type=${type} \
    downloadURL=\"$downloadURL\" \
    appNewVersion=${appNewVersion} \
    expectedTeamID=${expectedTeamID} \
    ${installomatorOptions} || true)"

checkCmdOutput $cmdOutput

# Mark: dockutil stuff
if [[ $addToDock -eq 1 ]]; then
    dialogUpdate "progresstext: Adding to Dock"
    if [[ ! -d $dockutil ]]; then
        echo "Cannot find dockutil at $dockutil, trying installation"
        # Install using Installlomator
        cmdOutput="$(${destFile} dockutil LOGO=$LOGO BLOCKING_PROCESS_ACTION=ignore LOGGING=REQ NOTIFY=silent || true)"
        checkCmdOutput $cmdOutput
    fi
    echo "Adding to Dock"
    $dockutil  --add "${appPath}" "${userHome}/Library/Preferences/com.apple.dock.plist" || true
    sleep 1
else
    echo "Not adding to Dock."
fi

# Mark: Ending
if [[ $installomatorVersion -lt 10 ]]; then
    echo "Again skipping Dialog stuff."
else
    # close and quit dialog
    dialogUpdate "progress: complete"
    dialogUpdate "progresstext: Done"

    # pause a moment
    sleep 0.5

    dialogUpdate "quit:"

    # let everything catch up
    sleep 0.5

    # just to be safe
    #killall "Dialog" 2>/dev/null || true
fi

echo "[$(DATE)][LOG-END]"

caffexit $exitStatus
