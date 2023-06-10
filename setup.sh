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


echo "Setup rule allowing SSH access to $MY_IP only"
aws ec2 authorize-security-group-ingress --group-name "$SEC_GRP" --port 22 --protocol tcp --source-group "$SEC_GRP" --cidr "$MY_IP"/32

echo "Setup rule allowing HTTP (port 5000) access to all IPs"
aws ec2 authorize-security-group-ingress --group-name "$SEC_GRP" --port 5000 --protocol tcp --source-group "$SEC_GRP" --cidr 0.0.0.0/0

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

PRIVATE_IP_1=$(aws ec2 describe-instances --instance-ids "$INSTANCE_ID_1" --query 'Reservations[0].Instances[0].PrivateIpAddress' --output text)

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

PRIVATE_IP_2=$(aws ec2 describe-instances --instance-ids "$INSTANCE_ID_2" --query 'Reservations[0].Instances[0].PrivateIpAddress' --output text)

echo "New instance 2 $INSTANCE_ID_2 @ $PUBLIC_IP_2"

AWS_ACCESS_KEY_ID=$(aws configure get aws_access_key_id)
AWS_SECRET_ACCESS_KEY=$(aws configure get aws_secret_access_key)
AWS_REGION=$(aws configure get region)

# echo "deploying code to production"
# scp -i $KEY_PEM -o "StrictHostKeyChecking=no" -o "ConnectionAttempts=60" main.py ubuntu@$PUBLIC_IP:/home/ubuntu/


echo "setup production environment for instance 1"
ssh -i $KEY_PEM -o "StrictHostKeyChecking=no" -o "ConnectionAttempts=10" ubuntu@$PUBLIC_IP_1 <<EOF
    sudo apt update
    sudo apt install python3-flask -y
    export FLASK_APP="main.py"
    # run app
    nohup flask run --host 0.0.0.0 &>/dev/null &
    exit
EOF

echo "setup production environment for instance 2"
ssh -i $KEY_PEM -o "StrictHostKeyChecking=no" -o "ConnectionAttempts=10" ubuntu@$PUBLIC_IP_2 <<EOF
    sudo apt update
    sudo apt install python3-flask -y
    export FLASK_APP="main.py"
    # run app
    nohup flask run --host 0.0.0.0 &>/dev/null &
    exit
EOF
