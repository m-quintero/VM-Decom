########################################################################
# Script Name: Azure VM Deletion Script
# Author: michael.quintero@rackspace.com
# Date: 2023-08-28
#
# Description: This script is designed to delete an Azure Virtual Machine (VM)
# and its associated resources. Option to create a snapshot as a final backup 
# before deletion.
#
# Usage:
# 1. Ensure Azure CLI is installed and you're logged in using `az login`.
# 2. Run the script: `bash azure_decom_runner.sh`
#    - Use flags -g for Resource Group, -v for VM name, and -i for instance type
#      e.g., `bash azure_decom_runner.sh -g MyResourceGroup -v MyVMName -i government`
# 3. If flags aren't used, follow the prompted inputs.
#
# Notes:
# - Assumes VM with a single NIC and OS disk.
# - Snapshots can incur costs. Monitor these resources.
# - Confirm prompts to prevent unintentional data loss.
########################################################################

#!/bin/bash

if ! command -v az &> /dev/null; then
    echo "Error: The az CLI is not installed or not in the PATH."
    exit 1
fi

backup_vm() {
    local resource_group="$1"
    local vm_name="$2"
    local snapshot_name="${vm_name}-final-backup"


    os_disk_id=$(az vm show --resource-group "$resource_group" --name "$vm_name" --query 'storageProfile.osDisk.managedDisk.id' -o tsv)


    if [[ $os_disk_id ]]; then
        az snapshot create --resource-group "$resource_group" --name "$snapshot_name" --source "$os_disk_id"
        echo "Snapshot $snapshot_name created successfully."
    else
        echo "Failed to create snapshot."
    fi
}


resource_group=""
vm_name=""
instance_type="commercial"  


while getopts "g:v:i:" opt; do
    case $opt in
        g) resource_group="$OPTARG" ;;
        v) vm_name="$OPTARG" ;;
        i) instance_type="$OPTARG" ;;
        *) echo "Invalid option: -$OPTARG" >&2
           exit 1
           ;;
    esac
done


[ -z "$resource_group" ] && read -p "Enter the Resource Group name: " resource_group
[ -z "$vm_name" ] && read -p "Enter the VM name: " vm_name
[ "$instance_type" != "commercial" ] && [ "$instance_type" != "government" ] && read -p "Is this a commercial or government instance? (Enter 'commercial' or 'government'): " instance_type


case $instance_type in
    "commercial")
        az cloud set --name AzureCloud
        ;;
    "government")
        az cloud set --name AzureUSGovernment
        ;;
    *)
        echo "Invalid instance type. Use 'commercial' or 'government'."
        exit 1
        ;;
esac


read -p "Would you like to create a final backup (snapshot) of the VM's OS disk before deletion [y/N]? " backup_confirmation

if [[ $backup_confirmation =~ ^[Yy]$ ]]; then
    backup_vm "$resource_group" "$vm_name"
fi


read -p "Are you sure you want to delete the VM and associated resources [y/N]? " delete_confirmation

if [[ $delete_confirmation =~ ^[Yy]$ ]]; then

    delete_associated_resources "$resource_group" "$vm_name"
else
    echo "Deletion aborted."
fi
