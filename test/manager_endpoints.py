from flask import Flask, request, jsonify
from threading import Timer
from queue import Queue
from datetime import datetime, timedelta
import subprocess
import requests
import json


app = Flask(__name__)
# this_manager = None


class Manager:
    def __init__(self):
        self.workQueue = Queue()
        self.workComplete = Queue()
        self.maxNumOfWorkers = 3
        self.numOfWorkers = 0
        self.timer = None
        self.otherManager = None
        self.lastWorkerSpawned = datetime.now()

    def add_sibling(self, manager):
        self.otherManager = manager

    def timer_10_sec(self):
        print("timer tick")
        if not self.workQueue.empty():
            work_item = self.workQueue.queue[0]
            # Check new worker wasn't already spawned in last 3 minutes (average up time)
            if datetime.now() - self.lastWorkerSpawned > timedelta(seconds=180):
                # check if work_item wasn't created is in queue for more than 30 seconds
                # TODO: if datetime.now() - work_item[2] > timedelta(seconds=30):
                if datetime.now() - work_item[2] > timedelta(seconds=1):
                    if self.numOfWorkers < self.maxNumOfWorkers:
                        self.spawnWorker()
                    else:
                        if self.otherManager.TryGetNodeQuota():
                            self.maxNumOfWorkers += 1

        # Schedule the next execution of timer_10_sec
        self.timer = Timer(1, self.timer_10_sec)
        # TODO: self.timer = Timer(10, self.timer_10_sec)
        self.timer.start()

    def start_timer(self):
        print("timer started")
        # Start the timer initially
        self.timer = Timer(1, self.timer_10_sec)
        # TODO: self.timer = Timer(10, self.timer_10_sec)
        self.timer.start()

    def stop_timer(self):
        # Stop the timer
        if self.timer is not None:
            self.timer.cancel()

    def spawnWorker(self):
        try:
            subprocess.run(['bash', 'setup_worker.sh'], check=True)
            # print("spawnWorker")
            self.lastWorkerSpawned = datetime.now()
        except subprocess.CalledProcessError as e:
            print(f"Failed to spawn worker: {e}")

    def TryGetNodeQuota(self, otherManager):
        return requests.get(f"{otherManager}/TryGetNodeQuota")

    def enqueueWork(self, data, iterations):
        self.workQueue.put((data, iterations, datetime.now()))

    def giveMeWork(self):
        return self.workQueue.get() or None

    def completed(self, result):
        self.workComplete.put(result)

    def pullComplete(self, top):
        result = []
        for i in range(top):
            if not self.workComplete.empty():
                result.append(self.workComplete.get())
            else:
                break
        if len(result) < top:
            missing_completed = str(top - len(result))
            url = f"http://{self.otherManager}/pullCompleteInternal?top={missing_completed}"
            response = requests.get(url)
            result.append(json.loads(response))
        return result

    def pullCompleteInternal(self, top):
        result = []
        for i in range(top):
            if not self.workComplete.empty():
                result.append(self.workComplete.get())
            else:
                break
        return result


@app.route('/enqueue', methods=['PUT'])
def enqueue():
    iterations = int(request.args.get('iterations'))
    data = request.get_data(as_text=True)
    this_manager.enqueueWork(data, iterations)
    return 'Work enqueued successfully'


@app.route('/pullCompleted', methods=['POST'])
def pull_completed():
    top = int(request.args.get('top'))
    results = this_manager.pullComplete(top)
    return jsonify(results)


@app.route('/internal/pullCompleteInternal', methods=['GET'])
def pull_complete_internal():
    top = int(request.args.get('top'))
    results = this_manager.pullCompleteInternal(top)
    return jsonify(results)


@app.route('/internal/giveMeWork', methods=['GET'])
def give_me_work():
    work_item = this_manager.giveMeWork()
    if work_item:
        return jsonify(work_item), 200
    else:
        return jsonify({'message': 'No available work'}), 404


@app.route('/internal/sendCompletedWork', methods=['POST'])
def send_completed_work():
    # Get the completed work from the request
    result = request.get_json()
    this_manager.completed(result)
    return 'Completed work added successfully'


@app.route('/addSibling', methods=['POST'])
def add_sibling():
    manager = request.args.get('manager')
    this_manager.add_sibling(manager)
    return 'Sibling added successfully'


@app.route('/internal/TryGetNodeQuota', methods=['GET'])
def try_get_node_quota():
    if this_manager.numOfWorkers < this_manager.maxNumOfWorkers:
        this_manager.maxNumOfWorkers -= 1
        return True
    return False


this_manager = Manager()
this_manager.start_timer()
app.run(host='0.0.0.0', port=5000, debug=True)
