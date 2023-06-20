from flask import Flask, request
from datetime import datetime
import requests
import time

app = Flask(__name__)


class Worker:
    instance_ip = None
    parent_ip = None









sqs = boto3.resource('sqs')
task_queue = sqs.get_queue_by_name(QueueName='task_queue')
result_queue = sqs.get_queue_by_name(QueueName='result_queue')


def perform_work(buffer, iterations):
    output = hashlib.sha512(buffer).digest()
    for _ in range(iterations - 1):
        output = hashlib.sha512(output).digest()
    return output


def process_tasks():
    while True:
        messages = task_queue.receive_messages(MaxNumberOfMessages=10)
        if not messages:
            continue

        for message in messages:
            task = json.loads(message.body)
            buffer = task['buffer']
            iterations = task['iterations']

            result = perform_work(buffer, iterations)

            result_message = {
                'work_id': message.message_id,
                'result': result
            }
            result_queue.send_message(MessageBody=json.dumps(result_message))

            message.delete()


if __name__ == '__main__':
    process_tasks()
