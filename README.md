# Cloud Computing - Exercise 2

## Students: Guy Ganot - 207044363 , Yotam Galinka - 318963931


# Dynamic_workload

## Building a queue & work management system for parallel processing

The project consists of two main files: load_balancer.py and worker.py. The load_balancer.py file represents the manager responsible for distributing tasks to worker nodes, while the worker.py file represents the worker nodes that perform the actual computation.

The load balancer code (load_balancer.py) sets up a Flask application and defines several routes for handling different tasks and requests. It includes functionalities such as initializing variables, enqueuing tasks, creating workers, checking and creating workers based on certain conditions, pulling completed tasks, getting sibling tasks, giving work to workers, marking work as done, and terminating workers.

The worker code (worker.py) also sets up a Flask application and defines a single route for starting the worker. The worker initializes itself, checks for work to do, processes the tasks by invoking the work function, and notifies the load balancer when work is done.

Additionally, there is a setup.sh script provided, which is responsible for deploying the project. It creates a key pair, sets up a security group, launches EC2 instances, and retrieves their public IP addresses.
