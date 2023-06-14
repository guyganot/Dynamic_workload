#!/bin/bash

# Run setup_manager.sh for the first time
echo "Running setup_manager.sh - First Run"
source ./setup_manager.sh
IP1="$PUBLIC_IP"

## Run setup_manager.sh for the second time
#echo "Running setup_manager.sh - Second Run"
#source ./setup_manager.sh
#IP2="$PUBLIC_IP"

echo "###Both instances are live###\n"

# Add siblings to each manager
curl -X POST "http://${IP1}:5000/addSibling?manager=${IP1}:5000"
#curl -X POST "http://${IP1}:5000/addSibling?manager=${IP2}:5000"
#curl -X POST "http://${IP2}:5000/addSibling?manager=${IP1}:5000"
