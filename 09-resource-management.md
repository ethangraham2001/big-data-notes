# 09 Resource Management

MapReduce is inefficient in several respects. For this reason, the architecture
was fundamentally changed by decoupling scheduling and monitoring - enter YARN.

Prior to this, the JobTracker had to deal with resource management, monitoring,
the job lifecycle, and fault tolerance. This is bad for scalability as it
introduces a single bottleneck.

## Yarn: Yet Another Resource Negotiator

Based on a centralized architecture wherein the coordinator node is called the
**ResourceManager** and the worker nodes are called the **NodeManagers**.
YARN provides generic support for allocating resources to any application - 
the ResourceManager will assign one of the containers to act as the
**ApplicationMaster** which takes care of running the application itself.
The ApplicationManager then communicates with the ResourceManager in order to
book and use more containers in order to run jobs.

We cleanly separate general management and bootstrapping new applications, 
which remains centralized on the ResourceManager. Monitoring the job lifecycle
is now delegated to one or more ApplicationMasters. We call this 
**multi-tenancy**.

## Resource Management

We will now answer the question _"what actually is resource management?"_
We will distinguish between four types of resources

- Memory
- CPU
- Disk I/O
- Netowrk I/O

Most resource management systems focus on the first two - managing I/O is an
open area of research.

ApplicationMasters can request and release containers at any time - this is
usually batched e.g. "gimme 10 containers with 2 cores and 16GB RAM each". This
request can be granted either fully or partially by the ResourceManager, which
is done indirectly by signing and issuing a token to the ApplicationMaster
which acts as proof that the request was granted. ApplicationMaster than 
connects to the responsible NodeManager with the token as authorization,
ships the code _(`.jar` file for example)_ and parameters which runs as a 
process on with exclusive use of this memory and CPU.

The ResourceManager can also issue external tokens to clients so that they can
bootstrap a new application by starting an ApplicationMaster.

## Job Lifecycle

In MapReduce

- ApplicationMaster requests containers for the map phase, sets them up to
    execute map tasks
- ApplicationMaster assigns a new map to a container from the remaining queue
    of map tasks until there are none left. _(note the subtle difference 
    between a slot and a container, as a container can have multiple slots)_.
- When the end of the map phase approaches, ApplicationMaster starts allocating
    containers for the reduce phase. When the map phase is complete, we can
    start issuing reduce tasks and free the map containers.
- Once the reduce phase is over, we can free the containers to YARN.

## Scheduling

The ResourceManager has to decide when to grant resource requests based on
capacity guarantees, fairness, SLAs. We want to maximize cluster utilization.

It provides an interface to clients and maintains a queue of applications with
their status, statistics, ... and an admin interface for configuring the queue.

ResourceManager should keep track of the list of available NodeManagers that
can run jobs. NodeManager communicate with ResourceManager via periodic
heartbeats. **The ResourceManager does not monitor tasks, or restart slots on
failure - this is the ApplicationMaster's job**.

### Strategies for scheduling

- **FIFO**
- **Capacity Scheduling:** partition cluster resources into sub-clusters of
    various sizes, each of which has its own FIFO of applications that are
    running. We can also have a hierarchical queue, where applications are
    scheduled with FIFO on the leaves of the queue. We can lso make this more
    dynamic where is a sub-cluster isn't currently used, its resources can be
    temporarily lent to the other sub-clusters.
- **Fair scheduling:** Think Linux CFS, which is an algorithm for fair 
    scheduling. We use factors like:

    - Steady fair share: static sub-clusters. We imagine that every sub-cluster
        uses the resources consistently
    - Instantaneous fair share: ideal allocation according to game theory 
        etc... dynamically changes based on sub-clusters being idle.
    - Current share: what is effectively being used by a cluster at any given
        point in time.

Easiest case of fair scheduling is only considering one resource at a time,
otherwise it gets very complex.

The problem was solved in practice using **Dominant Resource Fairness
algorithm**. We project two or more resources onto a single dimension by 
looking at which resource is dominant for each user. For example if a user
request 1% of memory and 0.1% of CPU, then the dominant resource if memory.
