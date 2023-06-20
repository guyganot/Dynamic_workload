KEY_NAME="cloud-course-`date +'%N'`"
KEY_PEM="$KEY_NAME.pem"

echo "create key pair $KEY_PEM to connect to instances and save locally"
aws ec2 create-key-pair --key-name $KEY_NAME \
    | jq -r ".KeyMaterial" > $KEY_PEM

# secure the key pair
chmod 400 $KEY_PEM

SEC_GRP="my-sg-`date +'%N'`"

echo "setup firewall $SEC_GRP"
aws ec2 create-security-group   \
    --group-name $SEC_GRP       \
    --description "Access my instances" 

# figure out my ip
MY_IP=$(curl ipinfo.io/ip)
echo "My IP: $MY_IP"


echo "Setup rule allowing SSH access to all IPs"
aws ec2 authorize-security-group-ingress --group-name "$SEC_GRP" --port 22 --protocol tcp --cidr 0.0.0.0/0

echo "Setup rule allowing HTTP (port 5000) access to all IPs"
aws ec2 authorize-security-group-ingress --group-name "$SEC_GRP" --port 5000 --protocol tcp --cidr 0.0.0.0/0

UBUNTU_20_04_AMI="ami-00aa9d3df94c6c354"

echo "Creating Ubuntu 20.04 instance 1..."
RUN_INSTANCE_1=$(aws ec2 run-instances   \
    --image-id $UBUNTU_20_04_AMI        \
    --instance-type t2.micro            \
    --key-name $KEY_NAME                \
    --security-groups $SEC_GRP)

INSTANCE_ID_1=$(echo $RUN_INSTANCE_1 | jq -r '.Instances[0].InstanceId')

echo "Waiting for instance 1 creation..."
aws ec2 wait instance-running --instance-ids $INSTANCE_ID_1

PUBLIC_IP_1=$(aws ec2 describe-instances  --instance-ids $INSTANCE_ID_1 | 
    jq -r '.Reservations[0].Instances[0].PublicIpAddress'
)

# PRIVATE_IP_1=$(aws ec2 describe-instances --instance-ids "$INSTANCE_ID_1" --query 'Reservations[0].Instances[0].PrivateIpAddress' --output text)

echo "New instance 1 $INSTANCE_ID_1 @ $PUBLIC_IP_1"

echo "Creating Ubuntu 20.04 instance 2..."
RUN_INSTANCE_2=$(aws ec2 run-instances   \
    --image-id $UBUNTU_20_04_AMI        \
    --instance-type t2.micro            \
    --key-name $KEY_NAME                \
    --security-groups $SEC_GRP)

INSTANCE_ID_2=$(echo $RUN_INSTANCE_2 | jq -r '.Instances[0].InstanceId')

echo "Waiting for instance 2 creation..."
aws ec2 wait instance-running --instance-ids $INSTANCE_ID_2

PUBLIC_IP_2=$(aws ec2 describe-instances  --instance-ids $INSTANCE_ID_2 | 
    jq -r '.Reservations[0].Instances[0].PublicIpAddress'
)

# PRIVATE_IP_2=$(aws ec2 describe-instances --instance-ids "$INSTANCE_ID_2" --query 'Reservations[0].Instances[0].PrivateIpAddress' --output text)

echo "New instance 2 $INSTANCE_ID_2 @ $PUBLIC_IP_2"

# AWS_ACCESS_KEY_ID=$(aws configure get aws_access_key_id)
# AWS_SECRET_ACCESS_KEY=$(aws configure get aws_secret_access_key)
# AWS_REGION=$(aws configure get region)

# echo "deploying code to production"
scp -i $KEY_PEM -o "StrictHostKeyChecking=no" -o "ConnectionAttempts=60" worker.py ubuntu@$PUBLIC_IP_1:/home/ubuntu/
scp -i $KEY_PEM -o "StrictHostKeyChecking=no" -o "ConnectionAttempts=60" load_balancer.py ubuntu@$PUBLIC_IP_1:/home/ubuntu/

scp -i $KEY_PEM -o "StrictHostKeyChecking=no" -o "ConnectionAttempts=60" worker.py ubuntu@$PUBLIC_IP_2:/home/ubuntu/
scp -i $KEY_PEM -o "StrictHostKeyChecking=no" -o "ConnectionAttempts=60" load_balancer.py ubuntu@$PUBLIC_IP_2:/home/ubuntu/

echo "setup production environment for instance 1"
ssh -i $KEY_PEM -o "StrictHostKeyChecking=no" -o "ConnectionAttempts=10" ubuntu@$PUBLIC_IP_1 <<EOF
    echo "export myIP=$PUBLIC_IP_1" >> ~/.bashrc
    echo "export siblingIP=$PUBLIC_IP_2" >> ~/.bashrc
    source ~/.bashrc
    exit
EOF

echo "setup production environment for instance 2"
ssh -i $KEY_PEM -o "StrictHostKeyChecking=no" -o "ConnectionAttempts=10" ubuntu@$PUBLIC_IP_2 <<EOF
    echo "export myIP=$PUBLIC_IP_2" >> ~/.bashrc
    echo "export siblingIP=$PUBLIC_IP_1" >> ~/.bashrc
    source ~/.bashrc
    exit
EOF


echo "setup production environment for instance 1"
ssh -i $KEY_PEM -o "StrictHostKeyChecking=no" -o "ConnectionAttempts=10" ubuntu@$PUBLIC_IP_1 <<EOF
    sudo apt update
    sudo apt install python
    sudo apt install python3-pip -y
    sudo apt install python3-paramiko -y
    sudo pip install Flask
    sudo pip install boto3
    sudo pip install requests
    export FLASK_APP="load_balancer.py"
    # run app
    nohup flask run --host 0.0.0.0 &>/dev/null &
    exit
EOF

echo "setup production environment for instance 2"
ssh -i $KEY_PEM -o "StrictHostKeyChecking=no" -o "ConnectionAttempts=10" ubuntu@$PUBLIC_IP_2 <<EOF
    sudo apt update
    sudo apt install python
    sudo apt install python3-pip -y
    sudo apt install python3-paramiko -y
    sudo pip install Flask
    sudo pip install boto3
    sudo pip install requests
    export FLASK_APP="load_balancer.py"
    # run app
    nohup flask run --host 0.0.0.0 &>/dev/null &
    exit
EOF


#!/bin/bash

# Generate unique names for IAM roles
timestamp=$(date +'%N')
IAM_ROLE_NAMES=("name-1-cloud-course-$timestamp" "name-2-cloud-course-$timestamp")

# IAM policy JSON
IAM_POLICY='{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:RunInstances",
        "ec2:TerminateInstances",
        "ec2:CreateKeyPair",
        "ec2:CreateSecurityGroup",
        "ec2:AuthorizeSecurityGroupIngress",
        "ec2:DescribeInstances",
        "ec2:DescribeInstanceStatus",
        "ec2:GetWaiter"
      ],
      "Resource": "*"
    }
  ]
}'

# Create IAM roles, policies, and instance profiles
IAM_ROLE_ARNS=()
IAM_POLICY_ARNS=()
for role_name in "${IAM_ROLE_NAMES[@]}"; do
  # Create IAM role
  IAM_ROLE_ARN=$(aws iam create-role --role-name "$role_name" --assume-role-policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"ec2.amazonaws.com"},"Action":"sts:AssumeRole"}]}' --query 'Role.Arn' --output text)
  IAM_ROLE_ARNS+=("$IAM_ROLE_ARN")

  # Create IAM policy
  IAM_POLICY_ARN=$(aws iam create-policy --policy-name "${role_name}-policy" --policy-document "$IAM_POLICY" --query 'Policy.Arn' --output text)
  IAM_POLICY_ARNS+=("$IAM_POLICY_ARN")

  # Attach IAM policy to IAM role
  aws iam attach-role-policy --role-name "$role_name" --policy-arn "$IAM_POLICY_ARN"

  # Create IAM instance profile
  aws iam create-instance-profile --instance-profile-name "$role_name"

  # Add IAM role to instance profile
  aws iam add-role-to-instance-profile --instance-profile-name "$role_name" --role-name "$role_name"
done

# Wait until instance profiles are available
for role_name in "${IAM_ROLE_NAMES[@]}"; do
  while ! aws iam get-instance-profile --instance-profile-name "$role_name" >/dev/null 2>&1; do
    sleep 1
  done
done

# Associate IAM instance profiles with EC2 instances
aws ec2 associate-iam-instance-profile --instance-id "$INSTANCE_ID_1" --iam-instance-profile Name="${IAM_ROLE_NAMES[0]}"
aws ec2 associate-iam-instance-profile --instance-id "$INSTANCE_ID_2" --iam-instance-profile Name="${IAM_ROLE_NAMES[1]}"

# Verify the IAM role and instance profile associations
aws ec2 describe-iam-instance-profile-associations --filters "Name=instance-id,Values=$INSTANCE_ID_1"
aws ec2 describe-iam-instance-profile-associations --filters "Name=instance-id,Values=$INSTANCE_ID_2"

echo "Created and attached IAM roles '${IAM_ROLE_NAMES[0]}' and '${IAM_ROLE_NAMES[1]}' to the EC2 instances."


curl -X POST "http://$PUBLIC_IP_1:5000/init_variables?my_ip=$PUBLIC_IP_1&sibling_ip=$PUBLIC_IP_2" &
curl -X POST "http://$PUBLIC_IP_2:5000/init_variables?my_ip=$PUBLIC_IP_2&sibling_ip=$PUBLIC_IP_1" &


echo "---------------------------------------------------------------------------"
echo "testing endpoints"
echo -e "enqueue work to the first instance by the command: curl -X PUT --data-binary \"@testing.bin\" \"http://$PUBLIC_IP_1:5000/enqueue?iterations=1\""
echo ""
curl -X PUT --data-binary "@testing.bin" "http://$PUBLIC_IP_1:5000/enqueue?iterations=1"
echo ""
echo -e "enqueue work to the first instance by the command: curl -X PUT --data-binary \"@testing.bin\" \"http://$PUBLIC_IP_OF_MY_INSTANCE_2:5000/enqueue?iterations=2\""
echo ""
curl -X PUT --data-binary "@testing.bin" "http://$PUBLIC_IP_2:5000/enqueue?iterations=2"
echo ""
echo "Waiting for 10 minutes...until the instances will be deployed.."
sleep 600
echo ""
echo -e "pull completed the 2 tasks from the first instance by the command: curl -X POST \"http://$PUBLIC_IP_OF_MY_INSTANCE_1:5000/pullCompleted?top=2\""
echo ""
curl -X POST "http://$PUBLIC_IP_1:5000/pullCompleted?top=2"
echo ""
