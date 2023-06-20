from flask import Flask, request
from datetime import datetime
import requests
import time

app = Flask(__name__)


class Worker:
    instance_id = None
    parent_ip = None
    nodesList = []

    @app.route('/start', methods=['PUT'])
    def start():
        parent = request.args.get('parentIP')
        machine = request.args.get('machineIP')
        Worker.instanceId = request.args.get('workerID')
        Worker.nodesList.append(parent)
        Worker.parent_ip = parent
        if machine is not None:
            Worker.nodesList.append(machine)
        lastWorkTime = datetime.now()
        while (datetime.now() - lastWorkTime).total_seconds() < 60:
            for n in Worker.nodesList:
                task = Worker.giveMeWork(n)
                if task['status'] != 0:
                    result = Worker.work(task['buffer'].encode('utf-8'), int(task['iterations']))
                    Worker.workDone(n, {'response': result.decode('latin-1')})
                    lastWorkTime = datetime.now()
                    continue
            time.sleep(1)
        Worker.terminate()




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

    @staticmethod
    def terminate():
        url = f"http://{Worker.parent_ip}:5000/terminate"
        requests.post(url, json={'id': Worker.instance_id})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
