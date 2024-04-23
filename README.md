# AWS EC2 Decommissioning Script

This script is used to automate the process of decommissioning AWS EC2 instances. It creates an AMI backup of the instance if needed, deletes the instance, and also deletes any EBS volumes attached to the instance.

## Prerequisites

- Bash shell
- AWS CLI installed and configured with necessary permissions

## Features

This script will do the following:

1. Prompt you whether to create an AMI backup of the instance(s) before deletion.
2. If you choose to create a backup, it will create an AMI and print a report with the instance ID, instance name, AMI ID, and AMI name. The AMI will have the TICKET = CHGXXXXXXX assigned as a tag
3. If you choose not to create a backup, it will still generate a report containing the instance ID, instance name, and any attached EBS volumes.
4. Then, the script will prompt you to proceed with instance and EBS volume deletion.
5. If you choose to proceed, the script will terminate the instance(s), wait for 1 minute to ensure the instance(s) are terminated, and then delete the EBS volumes.
6. After deleting the instances and volumes, it will generate a final report that includes the status of the instances and volumes.
7. Don't forget to chmod +x to the script
8. Use at your own risk! If you're not sure, ask a Linux peep


## Usage

You can run the script with the following options:

- `-c`: The change identifier.
- `-r`: The AWS region where the instance is located.
- `-i`: The ID of the instance(s) to decommission.

For example:
to decommission instance `i-0123456789abcdef0` in the `us-west-1` region, with change identifier `CHG0123456`, you would run:

```bash
./decom_runner.sh -c CHG0123456 -r us-west-1 -i "i-0123456789abcdef0"
```



# Azure VM Decommissioning Script

This script helps users easily delete Azure Virtual Machines (VMs) and associated resources. Additionally, it offers an option to take a snapshot as a final backup before VM deletion.

## Prerequisites

- [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli) installed and configured.
- Ensure you're authenticated to your Azure account using `az login`.

## Features

- Delete Azure VMs and their associated resources such as Network Interface and OS Disk.
- Option to take a snapshot of the VM's OS Disk before deletion.
- Set Azure environment based on user input (commercial or government).
- Command-line flags to specify VM details and bypass prompts.


## Usage

1. **Command-Line Flags**: The script supports the use of flags for a streamlined experience.

```bash
./azure_decom_runner.sh -g [Resource Group] -v [VM Name] -i [Instance Type: commercial/government]
```

For example:

```bash
./azure_decom_runner.sh -g MyResourceGroup -v MyVMName -i government
```

2. **Prompts**: If you don't provide flags, the script will prompt you for necessary details.

## Notes

- This script assumes a VM setup with a single NIC and OS Disk.
- Creating snapshots may incur additional Azure costs. Please monitor these resources.
- Always confirm prompts carefully to prevent unintentional data loss.
