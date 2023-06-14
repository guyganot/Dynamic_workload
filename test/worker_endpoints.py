import time
import sys
import requests
import hashlib
import subprocess


class Worker:
    def loop(self, managers):
        start_time = time.time()

        while time.time() - start_time <= 300:
            for i in range(len(managers)):
                work = self.giveMeWork(managers[i])
                if work is not None:
                    result = self.DoWork(work)
                    self.completed(managers[i], result)
                    start_time = time.time()
                    continue
            time.sleep(0.1)
        subprocess.call(["sudo", "shutdown", "now"])


    def DoWork(self, work):
        buffer = work[0]
        iterations = work[1]
        output = hashlib.sha512(buffer).digest()
        for i in range(iterations - 1):
            output = hashlib.sha512(output).digest()
        return output

        # Notify the parent that the Worker is done
        print("WorkerDone")

    def giveMeWork(self, manager):
        url = f"http://{manager}/internal/giveMeWork"
        try:
            response = requests.get(url)
            if response.status_code == 200:
                return response.json()
            else:
                print(f"Failed to retrieve work from {manager}")
        except requests.exceptions.RequestException as e:
            print(f"An error occurred while querying {manager}: {e}")
        return None

    def completed(self, node, result):
        url = f"http://{node}/internal/sendCompletedWork"
        response = requests.post(url, json=result)
        if response.status_code == 200:
            print('Completed work sent successfully')
        else:
            print('Failed to send completed work')

    # def start_worker(self):
    #     thread = Thread(target=worker.loop)
    #     thread.start()
    #     return 'Worker started', 200


if __name__ == '__main__':
    managers = [sys.argv[1], sys.argv[2]]
    worker = Worker()
    worker.loop()
