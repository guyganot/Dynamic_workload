from flask import Flask, request
from datetime import datetime
import requests
import time

app = Flask(__name__)

class Worker:
    instance_id = None
    parent_ip = None
    nodesList = []

    @staticmethod
    def start():
        worker = Worker()
        worker.run()

    def run(self):
        self.initialize_worker()
        while self.check_work_time():
            self.process_nodes()
            time.sleep(1)
        self.terminate()

    def initialize_worker(self):
        parent = request.args.get('parentIP')
        machine = request.args.get('machineIP')
        Worker.instance_id = request.args.get('workerID')
        Worker.nodesList.append(parent)
        Worker.parent_ip = parent
        if machine is not None:
            Worker.nodesList.append(machine)

    def check_work_time(self):
        last_work_time = datetime.now()
        return (datetime.now() - last_work_time).total_seconds() < 60

    def process_nodes(self):
        for n in Worker.nodesList:
            task = self.giveMeWork(n)
            if task['status'] != 0:
                result = self.work(task['buffer'].encode('utf-8'), int(task['iterations']))
                self.workDone(n, {'response': result.decode('latin-1')})

    @staticmethod
    def work(buffer, iterations):
        import hashlib
        output = hashlib.sha512(buffer).digest()
        for i in range(iterations - 1):
            output = hashlib.sha512(output).digest()
        return output

    @staticmethod
    def giveMeWork(ip):
        url = f"http://{ip}:5000/giveMeWork"
        try:
            response = requests.get(url)
            if response.status_code == 200:
                return response.json()
        except Exception as e:
            print(f"Error: {e}")
        return {"status": 0}

    @staticmethod
    def workDone(ip, output):
        url = f"http://{ip}:5000/workDone"
        requests.put(url, json=output)

    def terminate(self):
        url = f"http://{Worker.parent_ip}:5000/terminate"
        requests.post(url, json={'id': Worker.instance_id})


@app.route('/start', methods=['PUT'])
def start():
    Worker.start()
    return 'Worker started.'


if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
