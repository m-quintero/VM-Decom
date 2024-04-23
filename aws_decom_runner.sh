# AWS DECOM SCRIPT V2, AUTHOR: MIKE QUINTERO, michael.quintero@rackspace.com
# PURPOSE: To take a final AMI backup of the instance and print a report of the AMI name as well as any attached ebs volumes
# Usage: -c <CHANGE>, -r <REGION>, -i <INSTANCE>
# Example: Usage: ./aws_decom_runner.sh -c CHG0123456 -r us-west-1 -i "i-XXXXXXXXXXXX"

#!/bin/bash

while getopts c:r:i: flag
do
    case "${flag}" in
        c) CHANGE=${OPTARG};;
        r) REGION=${OPTARG};;
        i) INSTANCES=${OPTARG};;
    esac
done

# Convert change to lower case
CHANGE=$(echo $CHANGE | tr '[:upper:]' '[:lower:]')

# Convert instances input to lower case and create an array. Sometimes agencies enter serial names in all caps, AWS ebing case sensitive will not be happy
INSTANCES=($(echo $INSTANCES | tr '[:upper:]' '[:lower:]'))

# Set AWS region
export AWS_DEFAULT_REGION=$REGION

# Empty the final report file in case it exists from a previous run
echo "" > FINAL_REPORT.txt

# Function to generate the pre-op report
generate_report() {
    for instance in ${INSTANCES[@]}; do
        instance_name=$(aws ec2 describe-tags --filters "Name=resource-id,Values=$instance" "Name=key,Values=Name" --query 'Tags[].Value' --output text)
        echo "Instance ID: $instance, Instance Name: $instance_name" >> FINAL_REPORT.txt
        volumes=$(aws ec2 describe-instances --instance-ids $instance --query 'Reservations[].Instances[].BlockDeviceMappings[].Ebs.VolumeId' --output text)
        for volume in ${volumes[@]}; do
            echo "Instance ID: $instance, Instance Name: $instance_name, Volume ID: $volume" >> FINAL_REPORT.txt
        done
    done

    echo "Final report:"
    cat FINAL_REPORT.txt
}

# Initial prompt asking if the agency is requesting a backup. Important as these cost money, especially if they are tied to many EBS volumes
read -p "Do you want to create an AMI backup before instance deletion? (y/n): " create_ami

if [[ $create_ami == "y" || $create_ami == "Y" ]]; then
    for instance in ${INSTANCES[@]}; do

        # This will be used for name and description of the AMI
        INSTANCE_FINAL_BACKUP=${instance}_final_backup

        # Disable termination protection, just in case it's needed when we are deleting there here in a bit
        aws ec2 modify-instance-attribute --instance-id $instance --no-disable-api-termination

        # Create an AMI backup
        result=$(aws ec2 create-image --instance-id $instance --name "$INSTANCE_FINAL_BACKUP" --description "$INSTANCE_FINAL_BACKUP" --no-reboot --output text --query 'ImageId')

        # Tag the AMI with a key of 'Ticket' and value of '$CHANGE'
        aws ec2 create-tags --resources $result --tags Key=Ticket,Value=$CHANGE

        # Get the name of the EC2 instance
        instance_name=$(aws ec2 describe-tags --filters "Name=resource-id,Values=$instance" "Name=key,Values=Name" --query 'Tags[].Value' --output text)

        # Output the name of the AMI and instance ID to the final report
        echo "Instance ID: $instance, Instance Name: $instance_name, AMI ID: $result, AMI Name: $INSTANCE_FINAL_BACKUP" >> FINAL_REPORT.txt

        # Get information about the attached EBS volume(s)
        volumes=$(aws ec2 describe-instances --instance-ids $instance --query 'Reservations[].Instances[].BlockDeviceMappings[].Ebs.VolumeId' --output text)

        # Output the volume IDs to the final report
        for volume in ${volumes[@]}; do
            echo "Instance ID: $instance, Instance Name: $instance_name, Volume ID: $volume" >> FINAL_REPORT.txt
        done
    done

    # Print the contents of the final report
    echo "Final report:"
    cat FINAL_REPORT.txt
else
    echo "AMI creation skipped. Generating instance details report..."
    generate_report
fi

# Next prompt asking if ya wanna delete the instance and EBS volume(s)
read -p "Do you want to proceed with instance deletion and EBS volume deletion? (y/n): " proceed
if [[ $proceed == "y" || $proceed == "Y" ]]; then
    for instance in ${INSTANCES[@]}; do
        aws ec2 terminate-instances --instance-ids $instance
    done

    echo "Instances are being terminated. Waiting for 1 minute before deleting volumes..."
    sleep 60 # Wait for 1 minute

    # Delete EBS volumes after instance deletion
    volumes_to_delete=$(grep "Volume ID:" FINAL_REPORT.txt | awk '{print $9}')
    for volume in ${volumes_to_delete[@]}; do
        aws ec2 delete-volume --volume-id $volume 2>/dev/null
    done

# Function to query AWS CloudTrail for detailed instance and volume deletion events
cloudtrail_deletion_report() {
    echo "=== AWS CloudTrail Deletion Events Report ===" >> FINAL_REPORT_AFTER_DELETION.txt
    for instance in ${INSTANCES[@]}; do
        # Query for EC2 instance termination events
        event_result=$(aws cloudtrail lookup-events --lookup-attributes AttributeKey=ResourceName,AttributeValue=$instance --max-items 10 --query 'Events[?EventName==`TerminateInstances`]' --output json 2>/dev/null)

        if [[ ! -z "$event_result" && "$event_result" != "[]" ]]; then
            # Extracting and formatting event details
            event_time=$(echo "$event_result" | jq -r '.[0].EventTime')
            username=$(echo "$event_result" | jq -r '.[0].Username')
 #           source_ip=$(echo "$event_result" | jq -r '.[0].SourceIPAddress')
            event_source=$(echo "$event_result" | jq -r '.[0].EventSource')
            event_id=$(echo "$event_result" | jq -r '.[0].EventId')
            
            # Removed the following event type as it has changed (either removed or renamed on the aws side)  Source IP: $source_ip,)
            echo "Instance ID: $instance, Event: TerminateInstances, Time: $event_time, User: $username, Event Source: $event_source, Event ID: $event_id" >> FINAL_REPORT_AFTER_DELETION.txt
            
            # Query for EBS volume deletion events associated with the instance
            volumes=$(aws ec2 describe-instances --instance-ids $instance --query 'Reservations[].Instances[].BlockDeviceMappings[].Ebs.VolumeId' --output text)
            for volume in ${volumes[@]}; do
                volume_event_result=$(aws cloudtrail lookup-events --lookup-attributes AttributeKey=ResourceName,AttributeValue=$volume --max-items 10 --query 'Events[?EventName==`DeleteVolume`]' --output json 2>/dev/null)
                
                if [[ ! -z "$volume_event_result" && "$volume_event_result" != "[]" ]]; then
                    volume_event_time=$(echo "$volume_event_result" | jq -r '.[0].EventTime')
                    volume_username=$(echo "$volume_event_result" | jq -r '.[0].Username')
#                    volume_source_ip=$(echo "$volume_event_result" | jq -r '.[0].SourceIPAddress')
                    volume_event_source=$(echo "$volume_event_result" | jq -r '.[0].EventSource')
                    volume_event_id=$(echo "$volume_event_result" | jq -r '.[0].EventId')
            # Removed the following event type as it has changed (either removed or renamed on the aws side)  Source IP: $source_ip,)        
                    echo "Volume ID: $volume, Event: DeleteVolume, Time: $volume_event_time, User: $volume_username, Event Source: $volume_event_source, Event ID: $volume_event_id" >> FINAL_REPORT_AFTER_DELETION.txt
                fi
            done
        fi
    done
}
    echo "Instances and their EBS volumes have been deleted. Generating final report..."

# This part was tricky as I forgot about redirecting STDERR to STDOUT to be parsed for the sed action to clean up output
    echo "" > FINAL_REPORT_AFTER_DELETION.txt
    for instance in ${INSTANCES[@]}; do
        instance_status=$(aws ec2 describe-instances --instance-ids $instance --query 'Reservations[].Instances[].State.Name' --output text 2>/dev/null)
        echo "Instance ID: $instance, Instance Status: $instance_status" >> FINAL_REPORT_AFTER_DELETION.txt

        for volume in ${volumes_to_delete[@]}; do
      volume_status=$(aws ec2 describe-volumes --volume-ids $volume --query 'Volumes[].State' --output text 2>&1 >/dev/null)
            volume_status_filtered=$(echo "$volume_status" | sed -n -e 's/^.*operation: \(.*\)$/\1/p')
            echo "Volume ID: $volume, Volume Status: $volume_status_filtered" >> FINAL_REPORT_AFTER_DELETION.txt
  done
    done
    
    cloudtrail_deletion_report
    echo "Final report after deletion:"
    cat FINAL_REPORT_AFTER_DELETION.txt
else
    echo "Instance and EBS volume deletion aborted."
fi
