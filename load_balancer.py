import boto3
import json
import os
from flask import Flask, request
import threading
from datetime import datetime
import requests
import time
import uuid
import paramiko

app = Flask(__name__)

class Manager:
    my_ip = None
    sibling_ip = None
    task_queue = []
    completed_tasks = []
    num_of_workers = 0
    max_num_of_workers = 3  # total number of new workers
    limit = 3  # time in seconds to create new worker
    creating_worker = False  # does a worker is still in the process of creation

    @staticmethod
    def create_worker():
        worker_info = create_worker_route()
        return worker_info
    
    def create_worker_route():
        # Generate a random UUID
        worker_id = str(uuid.uuid4())
    
        # Set up EC2 client
        region = 'eu-west-1'
        ec2_client = boto3.client('ec2', region_name=region)
    
        # Create a key pair
        key_name = f'key-{worker_id}'
        response = ec2_client.create_key_pair(KeyName=key_name)
        key_material = response['KeyMaterial']
    
        # Save key material to a file
        key_file_path = f'{key_name}.pem'
        with open(key_file_path, 'w') as key_file:
            key_file.write(key_material)
    
        # Set up security group
        sg_name = f'sg-{worker_id}'
        response = ec2_client.create_security_group(
            Description='SG to access instances',
            GroupName=sg_name
        )
        security_group_id = response['GroupId']
    
        # Configure security group rules
        ec2_client.authorize_security_group_ingress(
            GroupId=security_group_id,
            IpPermissions=[
                {
                    'IpProtocol': 'tcp',
                    'FromPort': 5000,
                    'ToPort': 5000,
                    'IpRanges': [{'CidrIp': '0.0.0.0/0'}]
                },
                {
                    'IpProtocol': 'tcp',
                    'FromPort': 22,
                    'ToPort': 22,
                    'IpRanges': [{'CidrIp': '0.0.0.0/0'}]
                }
            ]
        )
    
        # Launch EC2 instance
        response = ec2_client.run_instances(
            ImageId='ami-00aa9d3df94c6c354',
            InstanceType='t2.micro',
            KeyName=key_name,
            SecurityGroupIds=[security_group_id],
            MinCount=1,
            MaxCount=1,
            UserData='''#!/bin/bash
                sudo apt update
                sudo apt install python3-pip -y
                sudo pip3 install Flask boto3 requests
                curl -O https://raw.githubusercontent.com/guyganot/Dynamic_workload/main/worker.py
                export FLASK_APP=worker.py
                nohup flask run --host 0.0.0.0 &>/dev/null &
                exit
                ''',
        )
        instance_id = response['Instances'][0]['InstanceId']
    
        # Wait for the instance to be ready
        waiter = ec2_client.get_waiter('instance_status_ok')
        waiter.wait(InstanceIds=[instance_id])
        print(f'Instance {instance_id} is running.')
    
        # Retrieve public IP address
        response = ec2_client.describe_instances(InstanceIds=[instance_id])
        public_ip = response['Reservations'][0]['Instances'][0]['PublicIpAddress']
    
        # Clean up key pair file
        os.remove(key_file_path)
    
        return f'(public_ip: {public_ip})'

    
    @app.route('/init_variables', methods=['POST'])
    def init_variables():
        if Manager.my_ip is not None or Manager.sibling_ip is not None:
            return 'Variables already initialized', 200
        
        Manager.my_ip = request.args.get('my_ip')
        Manager.sibling_ip = request.args.get('sibling_ip')
    
        if Manager.my_ip is not None and Manager.sibling_ip is not None:
            threading.Thread(target=Manager.timer_5_sec).start()
            return 'POST request processed successfully', 200
        else:
            return 'Invalid request parameters', 400


    @app.route('/enqueue', methods=['PUT'])
    def enqueue():
        iterations = request.args.get('iterations')
        buffer = request.get_data(as_text=True)
        enqueue_task(buffer, iterations)
        return 'PUT request processed successfully', 200

    def enqueue_task(buffer, iterations):
        Manager.task_queue.append((buffer, iterations, datetime.now()))
    
    @staticmethod
    def check_and_create_worker():
        if len(Manager.task_queue) > 0 and (datetime.now() - Manager.task_queue[0][2]).total_seconds() > Manager.limit:
            if Manager.num_of_workers < Manager.max_num_of_workers and not Manager.creating_worker:
                Manager.creating_worker = True
                Manager.num_of_workers += 1
                threading.Thread(target=Manager.create_worker).start()
            elif Manager.sibling_ip is not None and not Manager.creating_worker:
                try:
                    response = requests.get(f"http://{Manager.sibling_ip}:5000/tryGetNodeQuota")
                    if response.status_code == 200 and response.text == "True":
                        Manager.num_of_workers += 1
                        Manager.max_num_of_workers += 1
                        Manager.creating_worker = True
                        threading.Thread(target=Manager.create_worker).start()
                except Exception as e:
                    print(f"Error: {e}")

    @staticmethod
    def timer_5_sec():
        print()
        while True:
            Manager.check_and_create_worker()
            time.sleep(5)
                    
                    
    @app.route('/tryGetNodeQuota', methods=['GET'])
    def tryGetNodeQuota():
        if Manager.num_of_workers < Manager.max_num_of_workers:
            Manager.max_num_of_workers -= 1
            return "True"
        return "False"
    
    def get_completed_tasks(top):
        ListOfCompletedTask = []
    
        if top <= len(Manager.completed_tasks):
            ListOfCompletedTask = Manager.completed_tasks[:top]
            Manager.completed_tasks = Manager.completed_tasks[top:]
        elif Manager.sibling_ip is not None:
            completedTasksLeft = top - len(Manager.completed_tasks)
            ListOfCompletedTask = Manager.completed_tasks
            Manager.completed_tasks = []
    
            try:
                response = requests.get(f"http://{Manager.sibling_ip}:5000/getSiblingTasks?num={completedTasksLeft}")
                if response.status_code == 200:
                    siblingCompletedTasks = response.json()
                    ListOfCompletedTask += siblingCompletedTasks
            except Exception as e:
                print(f"Error: {e}")
    
        return ListOfCompletedTask

    @app.route('/pullCompleted', methods=['POST'])
    def pull_completed():
        top = int(request.args.get('top'))
        responseReturn = ""
        completed_tasks = get_completed_tasks(top)
    
        for index, task in enumerate(completed_tasks, start=1):
            responseReturn += f"\ntask #{index} output is: {task}, \n"
    
        return responseReturn

    def get_sibling_tasks(num_of_tasks):
        num_of_tasks = min(num_of_tasks, len(Manager.completed_tasks))
        completed_tasks_to_return = Manager.completed_tasks[:num_of_tasks]
        Manager.completed_tasks = Manager.completed_tasks[num_of_tasks:]
        return completed_tasks_to_return

    @app.route('/getSiblingTasks', methods=['GET'])
    def get_sibling_tasks_route():
        num_of_tasks = int(request.args.get('num'))
        completed_tasks = get_sibling_tasks(num_of_tasks)
        return completed_tasks
        
    def get_work():
        if len(Manager.task_queue) > 0:
            task = Manager.task_queue[0]
            Manager.task_queue = Manager.task_queue[1:]
            return {"buffer": task[0], "iterations": task[1], "status": 1}
        else:
            return {"status": 0}

    @app.route('/giveMeWork', methods=['GET'])
    def giveMeWork():
        work = get_work()
        return work
        
    @app.route('/workDone', methods=['PUT'])
    def workDone():
        response = request.get_json()['response']
        Manager.completed_tasks.append(response)
        return "worker finished"  
    
    def terminate_worker(worker_id):
        Manager.num_of_workers -= 1
        region = 'eu-west-1'
        ec2 = boto3.client('ec2', region_name=region)
        ec2.terminate_instances(InstanceIds=[worker_id])
        return "worker terminated with id: " + worker_id

    @app.route('/terminate', methods=['POST'])
    def terminate():
        worker_id = request.get_json()['id']
        termination_result = terminate_worker(worker_id)
        return termination_result
    
if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
