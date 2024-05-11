# AWS DECOM SCRIPT V3, AUTHOR: MIKE QUINTERO, michael.quintero@rackspace.com
# PURPOSE: To take a final AMI backup of the instance and print a report of the AMI name as well as any attached ebs volumes
# Usage: -c <CHANGE>, -r <REGION>, -i <INSTANCE>
# Example: Usage: ./aws_decom_runner.sh -c CHG0123456 -r us-west-1 -i i-XXXXXXXXXXXX

#!/bin/bash

while getopts c:r:i: flag
do
    case "${flag}" in
        c) CHANGE=${OPTARG};;
        r) REGION=${OPTARG};;
        i) INSTANCES=${OPTARG};;
    esac
done

CHANGE=$(echo $CHANGE | tr '[:upper:]' '[:lower:]')
INSTANCES=($(echo $INSTANCES | tr '[:upper:]' '[:lower:]'))
export AWS_DEFAULT_REGION=$REGION

DATE=$(date +%Y-%m-%d)
FINAL_REPORT_FILENAME="FINAL_REPORT_${CHANGE}_${DATE}.txt"
FINAL_REPORT_AFTER_DELETION_FILENAME="FINAL_REPORT_AFTER_DELETION_${CHANGE}_${DATE}.txt"

echo "" > $FINAL_REPORT_FILENAME

generate_report() {
    for instance in ${INSTANCES[@]}; do
        instance_name=$(aws ec2 describe-tags --filters "Name=resource-id,Values=$instance" "Name=key,Values=Name" --query 'Tags[].Value' --output text)
        echo "Instance ID: $instance, Instance Name: $instance_name" >> $FINAL_REPORT_FILENAME
        volumes=$(aws ec2 describe-instances --instance-ids $instance --query 'Reservations[].Instances[].BlockDeviceMappings[].Ebs.VolumeId' --output text)
        for volume in ${volumes[@]}; do
            echo "Instance ID: $instance, Instance Name: $instance_name, Volume ID: $volume" >> $FINAL_REPORT_FILENAME
        done
    done
    echo "Final report:"
    cat $FINAL_REPORT_FILENAME
}

read -p "Do you want to create an AMI backup before instance deletion? (y/n): " create_ami

if [[ $create_ami == "y" || $create_ami == "Y" ]]; then
    for instance in ${INSTANCES[@]}; do
        INSTANCE_FINAL_BACKUP=${instance}_final_backup
        aws ec2 modify-instance-attribute --instance-id $instance --no-disable-api-termination
        result=$(aws ec2 create-image --instance-id $instance --name "$INSTANCE_FINAL_BACKUP" --description "$INSTANCE_FINAL_BACKUP" --no-reboot --output text --query 'ImageId')
        aws ec2 create-tags --resources $result --tags Key=Ticket,Value=$CHANGE
        instance_name=$(aws ec2 describe-tags --filters "Name=resource-id,Values=$instance" "Name=key,Values=Name" --query 'Tags[].Value' --output text)
        echo "Instance ID: $instance, Instance Name: $instance_name, AMI ID: $result, AMI Name: $INSTANCE_FINAL_BACKUP" >> $FINAL_REPORT_FILENAME
        volumes=$(aws ec2 describe-instances --instance-ids $instance --query 'Reservations[].Instances[].BlockDeviceMappings[].Ebs.VolumeId' --output text)
        for volume in ${volumes[@]}; do
            echo "Instance ID: $instance, Instance Name: $instance_name, Volume ID: $volume" >> $FINAL_REPORT_FILENAME
        done
    done

    echo "Final report:"
    cat $FINAL_REPORT_FILENAME
else
    echo "AMI creation skipped. Generating instance details report..."
    generate_report
fi

read -p "Do you want to proceed with instance deletion and EBS volume deletion? (y/n): " proceed
if [[ $proceed == "y" || $proceed == "Y" ]]; then
    for instance in ${INSTANCES[@]}; do
        aws ec2 terminate-instances --instance-ids $instance
    done

    echo "Instances are being terminated. Waiting for 30 seconds before deleting volumes..."
    sleep 30 

    volumes_to_delete=$(grep "Volume ID:" $FINAL_REPORT_FILENAME | awk '{print $9}')
    for volume in ${volumes_to_delete[@]}; do
        aws ec2 delete-volume --volume-id $volume 2>/dev/null
    done

    echo "Waiting for an additional 1 minute for CloudTrail to log the events..."
    sleep 60

    echo "" > $FINAL_REPORT_AFTER_DELETION_FILENAME
    cloudtrail_deletion_report() {
        echo "=== AWS CloudTrail Deletion Events Report ===" >> $FINAL_REPORT_AFTER_DELETION_FILENAME
        for instance in ${INSTANCES[@]}; do
            event_result=$(aws cloudtrail lookup-events --lookup-attributes AttributeKey=ResourceName,AttributeValue=$instance --max-items 10 --query 'Events[?EventName==`TerminateInstances`]' --output json 2>/dev/null)
            if [[ ! -z "$event_result" && "$event_result" != "[]" ]]; then
                event_time=$(echo "$event_result" | jq -r '.[0].EventTime')
                username=$(echo "$event_result" | jq -r '.[0].Username')
                event_source=$(echo "$event_result" | jq -r '.[0].EventSource')
                event_id=$(echo "$event_result" | jq -r '.[0].EventId')
                echo "Instance ID: $instance, Event: TerminateInstances, Time: $event_time, User: $username, Event Source: $event_source, Event ID: $event_id" >> $FINAL_REPORT_AFTER_DELETION_FILENAME
            else
                echo "No Termination Events Found for Instance ID: $instance" >> $FINAL_REPORT_AFTER_DELETION_FILENAME
            fi
            instance_status=$(aws ec2 describe-instances --instance-ids $instance --query 'Reservations[].Instances[].State.Name' --output text 2>/dev/null)
            echo
            echo "Instance ID: $instance, Instance Status: $instance_status" >> $FINAL_REPORT_AFTER_DELETION_FILENAME
            echo
            for volume in ${volumes_to_delete[@]}; do
                volume_status=$(aws ec2 describe-volumes --volume-ids $volume --query 'Volumes[].State' --output text 2>&1 >/dev/null)
                volume_status_filtered=$(echo "$volume_status" | sed -n -e 's/^.*operation: \(.*\)$/\1/p')
                echo
                echo "Volume ID: $volume, Volume Status: $volume_status_filtered" >> $FINAL_REPORT_AFTER_DELETION_FILENAME
                echo
            done
        done
    }
    cloudtrail_deletion_report
    echo "Instances and their EBS volumes have been deleted. Generating final report..."
    cat $FINAL_REPORT_AFTER_DELETION_FILENAME
else
    echo "Instance and EBS volume deletion aborted."
fi
