import boto3
import json
import os
from flask import Flask, request

app = Flask(__name__)
sqs = boto3.resource('sqs')
task_queue = sqs.get_queue_by_name(QueueName='task_queue')
result_queue = sqs.get_queue_by_name(QueueName='result_queue')


@app.route('/enqueue', methods=['PUT'])
def enqueue_work():
    iterations = int(request.args.get('iterations'))
    buffer = request.data

    message = {
        'buffer': buffer,
        'iterations': iterations
    }

    response = task_queue.send_message(MessageBody=json.dumps(message))
    return response['MessageId']


@app.route('/pullCompleted', methods=['POST'])
def pull_completed_work():
    num = int(request.args.get('top'))
    completed_work = []

    while num > 0:
        messages = result_queue.receive_messages(MaxNumberOfMessages=1)
        if not messages:
            break

        for message in messages:
            result = json.loads(message.body)
            completed_work.append(result)
            message.delete()
            num -= 1

    return json.dumps(completed_work)


if __name__ == '__main__':
    app.run()
