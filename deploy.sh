#!/bin/bash
echo "
##############################################################################################################
#
# Deployment of a Fortigate Active/Active cluster
#
##############################################################################################################

"
echo "--> Auto accepting terms for Azure Marketplace deployments ..."
#az vm image accept-terms --publisher fortinet --offer fortinet_fortigate-vm_v5 --plan fortinet_fg-vm
#az vm image accept-terms --publisher fortinet --offer fortinet-fortianalyzer --plan fortinet-fortianalyzer

# Stop on error
set +e

if [ -z "$DEPLOY_LOCATION" ]
then
    # Input location 
    echo -n "Enter location (e.g. eastus2): "
    stty_orig=`stty -g` # save original terminal setting.
    read location         # read the location
    stty $stty_orig     # restore terminal setting.
    if [ -z "$location" ] 
    then
        location="eastus2"
    fi
else
    location="$DEPLOY_LOCATION"
fi
echo ""
echo "--> Deployment in $location location ..."
echo ""

if [ -z "$DEPLOY_PREFIX" ]
then
    # Input prefix 
    echo -n "Enter prefix: "
    stty_orig=`stty -g` # save original terminal setting.
    read prefix         # read the prefix
    stty $stty_orig     # restore terminal setting.
    if [ -z "$prefix" ] 
    then
        prefix="FORTI"
    fi
else
    prefix="$DEPLOY_PREFIX"
fi
echo ""
echo "--> Using prefix $prefix for all resources ..."
echo ""
rg="$prefix-RG"

if [ -z "$DEPLOY_PASSWORD" ]
then
    # Input password 
    echo -n "Enter password: "
    stty_orig=`stty -g` # save original terminal setting.
    stty -echo          # turn-off echoing.
    read passwd         # read the password
    stty $stty_orig     # restore terminal setting.
else
    passwd="$DEPLOY_PASSWORD"
    echo ""
    echo "--> Using password found in env variable DEPLOY_PASSWORD ..."
    echo ""
fi

if [ -z "$DEPLOY_USERNAME" ]
then
    username="azureuser"
else
    username="$DEPLOY_USERNAME"
fi
echo ""
echo "--> Using username '$username' ..."
echo ""

license=''
if [ -f "license/fgt.lic" ]; then
   echo "Loading license file license/fgt.lic."
   license=`cat license/fgt.lic`
fi

# Create resource group
echo ""
echo "--> Creating $rg resource group ..."
az group create --location "$location" --name "$rg"

# Validate template
echo "--> Validation deployment in $rg resource group ..."
az group deployment validate --resource-group "$rg" \
                           --template-file azuredeploy.json \
                           --parameters prefix=$prefix adminUsername=$username adminPassword=$passwd fortigateLicense="$license"
result=$? 
if [ $result != 0 ]; 
then 
    echo "--> Validation failed ..."
    exit $rc; 
fi

# Deploy resources
echo "--> Deployment of $rg resources ..."
az group deployment create --resource-group "$rg" \
                           --template-file azuredeploy.json \
                           --parameters prefix=$prefix adminUsername=$username adminPassword=$passwd fortigateLicense="$license"
result=$? 
if [[ $result != 0 ]]; 
then 
    echo "--> Deployment failed ..."
    exit $rc; 
else 
echo "
##############################################################################################################
 IP Assignment:
"
query="[?virtualMachine.name.starts_with(@, '$prefix')].{virtualMachine:virtualMachine.name, publicIP:virtualMachine.network.publicIpAddresses[0].ipAddress,privateIP:virtualMachine.network.privateIpAddresses[0]}"
az vm list-ip-addresses --query "$query" --output tsv
echo "
##############################################################################################################
"
fi

host = `az vm show -d -g "$rg" -n "$prefix-FGT" --query publicIps -o tsv`
fgt_external_ip = `az network nic show -g "$rg" -n "$prefix-FGT-Nic1" --query "ipConfigurations[0].privateIpAddress" -o tsv`
faz_internal_ip = `az network nic show -g "$rg" -n "$prefix-FAZ-Nic" --query "ipConfigurations[0].privateIpAddress" -o tsv`
lnx_internal_ip = `az network nic show -g "$rg" -n "$prefix-FGT-Nic" --query "ipConfigurations[0].privateIpAddress" -o tsv`
vnet = `az network vnet show -g "$rg" -n "$prefix-VNET" --query "addressSpace.addressPrefixes[0]" -o tsv`
#
ansible-playbook /data/fortigate_config.yml -vvv \
                --extra-vars "host=$host prefix=$prefix username=$username password=$password vnet=$vnet fgt_external_ip=$fgt_external_ip faz_internal_ip=$faz_internal_ip lnx_internal_ip=$lnx_internal_ip"
#

exit 0