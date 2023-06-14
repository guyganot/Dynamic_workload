#!/bin/bash

set -euo pipefail

aws configure set region us-east-1

# Create key pair to connect to instances and save locally
printf "Creating key pair...\n"
KEY_NAME="cloud-course-ex-2-$(date +'%N')"
KEY_PEM="$KEY_NAME.pem"
printf "Key name: %s\n" "$KEY_NAME"
aws ec2 create-key-pair --key-name "$KEY_NAME" --region us-east-1 | jq -r ".KeyMaterial" > "$KEY_PEM"
chmod 400 "$KEY_PEM"

# Setup firewall
printf "Setting up firewall...\n"
SEC_GRP="my-sg-$(date +'%N')"
printf "Security group name: %s\n" "$SEC_GRP"
aws ec2 create-security-group --group-name "$SEC_GRP" --description "Access my instances"  --region us-east-1

# Figure out my IP
MY_IP="$(curl ipinfo.io/ip)"
printf "My IP: %s\n" "$MY_IP"

# Setup rule allowing SSH access to MY_IP only
printf "Setting up firewall rules...\n"
aws ec2 authorize-security-group-ingress --group-name "$SEC_GRP" --port 22 --protocol tcp --cidr "$MY_IP/32"
# #
# # Setup rule allowing HTTP (port 5000) access to MY_IP only
# aws ec2 authorize-security-group-ingress --group-name "$SEC_GRP" --port 5000 --protocol tcp --cidr "$MY_IP/32"

# Setup rule allowing HTTP (port 5000) access to all IPs
aws ec2 authorize-security-group-ingress --group-name "$SEC_GRP" --port 5000 --protocol tcp --cidr 0.0.0.0/0

# Set AMI ID and instance type
UBUNTU_22_04_AMI="ami-00aa9d3df94c6c354"
INSTANCE_TYPE="t2.micro"

# Create Ubuntu 22.04 instance
printf "Creating Ubuntu 22.04 instance...\n"
RUN_INSTANCES=$(aws ec2 run-instances --image-id "$UBUNTU_22_04_AMI" --instance-type "$INSTANCE_TYPE" --instance-initiated-shutdown-behavior terminate --key-name "$KEY_NAME" --security-groups "$SEC_GRP")
INSTANCE_ID=$(echo "$RUN_INSTANCES" | jq -r '.Instances[0].InstanceId')

# Wait for instance creation
printf "Waiting for instance creation...\n"
aws ec2 wait instance-running --instance-ids "$INSTANCE_ID"
PUBLIC_IP=$(aws ec2 describe-instances --instance-ids "$INSTANCE_ID" | jq -r '.Reservations[0].Instances[0].PublicIpAddress')
printf "New instance %s @ %s\n" "$INSTANCE_ID" "$PUBLIC_IP"


# Deploy code to production
printf "Deploying code to production...\n"
APP_FILE="worker-endpoints.py"
scp -i $KEY_PEM -o "StrictHostKeyChecking=no" -o "ConnectionAttempts=60" worker-endpoints.py ubuntu@$PUBLIC_IP:/home/ubuntu/


# SSH into the instance and run the necessary commands  to deploy the app
printf "\n"
printf "########Running this command: ssh -T -i $KEY_PEM ubuntu@$PUBLIC_IP########\n"
ssh -T -i "$KEY_PEM" -o "StrictHostKeyChecking=no" -o "ConnectionAttempts=10" ubuntu@"$PUBLIC_IP" << EOF
    sudo apt update
    sudo apt install python3-pip -y
    sudo pip install Flask
    export FLASK_APP=$APP_FILE
    nohup flask run --host 0.0.0.0  &>/dev/null &
    exit
EOF
