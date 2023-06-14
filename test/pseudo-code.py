class EndpointNode:
    workQueue = []
    workComplete = []
    maxNumOfWorkers = 0
    numOfWorkers = 0

    # def __init__(self) -> None:
    #
    #     if self is Avishag:
    #         sleep(3
    #         min)
    #
    #         pass

    # def add_sibling(other):
    #     pass

    def timer_10_sec():
        # rate limit - number of new workers per time period
        # rate limit - total number of new workers
        if Date.now - workQueue.peek().time > 15sec:
            if numOfWorkers < maxNumOfWorkers:
                spawnWorker()
            else:
                if otherNode.TryGetNodeQuota():
                    maxNumOfWorkers += 1

    def TryGetNodeQuota():
        if numOfWorkers < maxNumOfWorkers:
            maxNumOfWorkers -= 1
            return True
        return False

    def enqueueWork(text, iterations):
        workQueue.push((text, iterations, Date.now()))

    def giveMeWork():
        return workQueue.pop() or None

    def pullComplete(n):
        results = workComplete.take(n)
        if len(results) > 0:
            return results
        try:
            return otherNode.pullCompleteInternal(n)
        except:
            return []

class Worker:

    # ec2 - terminate on shutdown

    def DoWork(t):

        pass

    def loop():

        nodes = [Noa, Avishag]

        lastTime = Date.now

        while Date.Now - lastTime <= 10Min:

            for i in range(nodes):

                work = nodes[i].giveMeWork()

                if work != None:
                    result = DoWork(work)

                    nodes[i].completed(result)

                    lastTime = Date.now

                    continue

            sleep(100)

        parent.WorkerDone()


# nohup python3 my-script.py noa avishag
# a = spawn_endpoint
# b = spawn_endpoint
# a.add_Sibling(b)
# b.add_Sibling(a)

Noa = EndpointNode(2, me: 'noa', other: 'avishag')
Avishag = EndpointNode(3, me: 'avishag', other: 'noa')

# curl http://noa-ip/enqueue
# curl http://avishag-ip/pullComplete

# for i in range(25):
# Noa.enqueueWork("cup", 30)
#
# for i in range(25):
# Avishag.enqueueWork("cup", 30)
#
# for i in range(2500):
# Noa.enqueueWork("cup", 30)
#
# while True:
# result = Avishag.pullComplete(10)
#
# print(result)
