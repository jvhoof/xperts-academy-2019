#!/bin/bash
echo "
##############################################################################################################
#
# Run Ansible configuration script for the Fortinet IOC demo
#
##############################################################################################################

"
function usage {
    printf "%s\n" "usage: $0 [-d] [-p playbookfilename] [-o outfile]"
    printf "%s\n" "  -d      use the docker image jvhoof/cloud-essentials to run Ansible"
    printf "%s\n" "  -p      use the provided playbookfile (included path)"
    printf "%s\n" "  -s      quiet mode\n"
    exit 1
}
error_handle() {
  stty echo;
}

DOCKER=""
while getopts "dp:su" option; do
    case "${option}" in
        d) 
            printf "%s\n" "--> Using docker container jvhoof/cloud-essentials"
            DOCKER="docker run --rm -itv $PWD:/data jvhoof/cloud-essentials:latest " 
        ;;
        p) PLAYBOOK="$OPTARG" ;;
        s)
            stty -echo;
            trap error_handle INT;
            trap error_handle TERM;
            trap error_handle KILL;
            trap error_handle EXIT;
        ;;
        u) usage && exit 0 ;;
        \?)
            printf "%s\n" "Invalid option: -$OPTARG" >&2
            exit 1
            ;;
    esac
done

# If playbook file location is empty use default
if [ -z "$PLAYBOOK" ]
then
    if [ -z "$DOCKER" ]
    then
        PLAYBOOKDIR="ansible"
    else
        PLAYBOOKDIR="/data/ansible"
    fi
    PLAYBOOK="$PLAYBOOKDIR/fortigate_config.yml"
    printf "%s\n" "--> Ansible playbook location [$PLAYBOOK]"
fi

if [ -z "$DEPLOY_LOCATION" ]
then
    # Input location 
    echo -n "Enter location (e.g. eastus2): "
    stty_orig=`stty -g` # save original terminal setting.
    read location         # read the location
    stty %stty_orig     # restore terminal setting.
    if [ -z "$location" ] 
    then
        location="eastus2"
    fi
else
    location="$DEPLOY_LOCATION"
fi
printf "%s\n" "--> Deployment in '$location' location ..."

if [ -z "$DEPLOY_PREFIX" ]
then
    # Input prefix 
    echo -n "Enter prefix: "
    stty_orig=`stty -g` # save original terminal setting.
    read prefix         # read the prefix
    stty %stty_orig     # restore terminal setting.
    if [ -z "$prefix" ] 
    then
        prefix="FORTI"
    fi
else
    prefix="$DEPLOY_PREFIX"
fi
printf "%s\n" "--> Using prefix '$prefix' for all resources ..."
rg="$prefix-RG"

if [ -z "$DEPLOY_PASSWORD" ]
then
    # Input password 
    echo -n "Enter password: "
    stty_orig=`stty -g` # save original terminal setting.
    stty -echo          # turn-off echoing.
    read passwd         # read the password
    stty %stty_orig     # restore terminal setting.
else
    passwd="$DEPLOY_PASSWORD"
    printf "%s\n" "--> Using password found in env variable DEPLOY_PASSWORD ..."
fi

if [ -z "$DEPLOY_USERNAME" ]
then
    username="azureuser"
else
    username="$DEPLOY_USERNAME"
fi
echo "--> Using username 'username' ..."

host=`az vm show -d -g "$rg" -n "$prefix-FGT" --query publicIps -o tsv`
printf "%s\n" "--> Using host '$host' ..."
fgt_external_ip=`az network nic show -g "$rg" -n "$prefix-FGT-Nic1" --query "ipConfigurations[0].privateIpAddress" -o tsv`
printf "%s\n" "--> Using fgt_external_ip '$fgt_external_ip' ..."
faz_internal_ip=`az network nic show -g "$rg" -n "$prefix-FAZ-Nic" --query "ipConfigurations[0].privateIpAddress" -o tsv`
printf "%s\n" "--> Using faz_internal_ip '$faz_internal_ip' ..."
lnx_internal_ip=`az network nic show -g "$rg" -n "$prefix-LNX-Nic" --query "ipConfigurations[0].privateIpAddress" -o tsv`
printf "%s\n" "--> Using lnx_internal_ip '$lnx_internal_ip' ..."
vnet=`az network vnet show -g "$rg" -n "$prefix-VNET" --query "addressSpace.addressPrefixes[0]" -o tsv`
printf "%s\n" "--> Using vnet '$vnet' ..."
rg="$prefix-RG"
#

printf "%s\n" "==> Running Ansible"
$DOCKER ansible-playbook "$PLAYBOOK" \
                    --extra-vars "host=$host prefix=$prefix username=$username password=$passwd vnet=$vnet fgt_external_ip=$fgt_external_ip faz_internal_ip=$faz_internal_ip lnx_internal_ip=$lnx_internal_ip"

exit 0