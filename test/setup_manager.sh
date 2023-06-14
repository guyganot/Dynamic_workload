#!/bin/bash

set -euo pipefail

# Create key pair to connect to instances and save locally
printf "Creating key pair...\n"
KEY_NAME="cloud-course-assignment-2-$(date +'%N')"
KEY_PEM="$KEY_NAME.pem"
printf "Key name: %s\n" "$KEY_NAME"
aws ec2 create-key-pair --key-name "$KEY_NAME" | jq -r ".KeyMaterial" > "$KEY_PEM"
chmod 400 "$KEY_PEM"

# Setup firewall
printf "Setting up firewall...\n"
SEC_GRP="my-sg-$(date +'%N')"
printf "Security group name: %s\n" "$SEC_GRP"
aws ec2 create-security-group --group-name "$SEC_GRP" --description "Access my instances"

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

# Define the IAM role name and policy
ROLE_NAME="MyEC2Role-$(date +'%N')"
POLICY_NAME="MyEC2Policy-$(date +'%N')"
INSTANCE_PROFILE_NAME="MyEC2InstanceProfile-$(date +'%N')"
ASSUME_ROLE_DOCUMENT='{"Version": "2012-10-17", "Statement": [{"Effect": "Allow", "Principal": {"Service": "ec2.amazonaws.com"}, "Action": "sts:AssumeRole"}]}'
# TODO: Remove unnecessary permissions
POLICY_DOCUMENT='{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:CreateSecurityGroup",
        "ec2:AuthorizeSecurityGroupIngress",
        "ec2:RunInstances",
        "ec2:DescribeInstances",
        "ec2:CreateKeyPair",
        "ec2:Wait",
        "ec2:DescribeInstanceStatus",
        "ec2:DescribeInstanceAttribute",
        "ec2:DescribeKeyPairs",
        "ec2:DescribeSecurityGroups",
        "ec2:TerminateInstances",
        "ec2:DeleteSecurityGroup"
      ],
      "Resource": "*"
    }
  ]
}'

# Create the IAM role
aws iam create-role --role-name "$ROLE_NAME" --assume-role-policy-document "$ASSUME_ROLE_DOCUMENT"

# Create the IAM policy
aws iam create-policy --policy-name "$POLICY_NAME" --policy-document "$POLICY_DOCUMENT"

# Attach the policy to the role
aws iam attach-role-policy --role-name "$ROLE_NAME" --policy-arn "$(aws iam list-policies --query "Policies[?PolicyName=='$POLICY_NAME'].Arn" --output text)"

# Create the IAM instance profile
aws iam create-instance-profile --instance-profile-name "$INSTANCE_PROFILE_NAME"

# Add the IAM role to the instance profile
aws iam add-role-to-instance-profile --role-name "$ROLE_NAME" --instance-profile-name "$INSTANCE_PROFILE_NAME"

# Wait for the instance profile to be created
sleep 3

# Remove the "role/" prefix from the ARN to form the instance profile ARN
INSTANCE_PROFILE_ARN=$(aws iam get-instance-profile --instance-profile-name "$INSTANCE_PROFILE_NAME" --query "InstanceProfile.Arn" --output text)

# Create Ubuntu 22.04 instance
printf "Creating Ubuntu 22.04 instance...\n"
RUN_INSTANCES=$(aws ec2 run-instances --image-id "$UBUNTU_22_04_AMI" --instance-type "$INSTANCE_TYPE" --key-name "$KEY_NAME" --iam-instance-profile "Arn=$INSTANCE_PROFILE_ARN" --security-groups "$SEC_GRP")
INSTANCE_ID=$(echo "$RUN_INSTANCES" | jq -r '.Instances[0].InstanceId')

# Wait for instance creation
printf "Waiting for instance creation...\n"
aws ec2 wait instance-running --instance-ids "$INSTANCE_ID"
PUBLIC_IP=$(aws ec2 describe-instances --instance-ids "$INSTANCE_ID" | jq -r '.Reservations[0].Instances[0].PublicIpAddress')
export PUBLIC_IP
printf "New instance %s @ %s\n" "$INSTANCE_ID" "$PUBLIC_IP"

# Deploy code to production
printf "Deploying code to production...\n"
APP_FILE="manager_endpoints.py"
# scp -i $KEY_PEM -o "StrictHostKeyChecking=no" -o "ConnectionAttempts=60" ./ ubuntu@$PUBLIC_IP:/home/ubuntu/
scp -i $KEY_PEM -o "StrictHostKeyChecking=no" -o "ConnectionAttempts=60" manager_endpoints.py setup_worker.sh worker_endpoints.py ubuntu@$PUBLIC_IP:/home/ubuntu/


# SSH into the instance and run the necessary commands  to deploy the app
printf "\n"
printf "########Running this command: ssh -T -i $KEY_PEM ubuntu@$PUBLIC_IP########\n"
ssh -T -i "$KEY_PEM" -o "StrictHostKeyChecking=no" -o "ConnectionAttempts=10" ubuntu@"$PUBLIC_IP" << EOF
    sudo apt update
    sudo apt install python3-pip -y

    wget https://github.com/stedolan/jq/releases/download/jq-1.6/jq-linux64 -O jq
    chmod +x jq
    sudo mv jq /usr/local/bin

    sudo pip3 install awscli

    sudo pip install Flask
    export FLASK_APP=$APP_FILE
    nohup flask run --host=0.0.0.0 --port=5000
EOF

#    TODO: nohup flask run --host=0.0.0.0 --port=5000  &>/dev/null &
#    exit
