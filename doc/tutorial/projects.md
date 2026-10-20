(tutorial-projects)=
# Projects

In the {ref}`previous part of the tutorial <tutorial-instances>`, you learned how to create and work with instances.

When you are managing lots of instances providing different services, it can become confusing to see which instances are dependent on each other.

The projects feature is designed to help in this situation by providing the ability to group one or more instances together into related "projects" that can be used with the `lxc` CLI or the UI.

This part of the tutorial will show how to create LXD projects, add instances into a project, and explore the features that can be specified at a project level.

(tutorial-project-create)=
## Creating our first project

Imagine we have a scenario where we are setting up a web site for a particular client.
We want to create two instances; one for the web service and one for the database service.
Because we have lots of different web sites for different clients we want to ensure that we can quickly see and manage all of the containers for this particular web site.

Projects help us in this situation because we can create a project called `client-website` and use that project to organize instances related to the client's web site.

```bash
lxc project create client-website --config features.images=false --config features.profiles=false
```

In the above command we have used the `--config` flag to set the {config:option}`project-features:features.images` and {config:option}`project-features:features.profiles` to `false` so that our new project will still use the images and profiles of the default project and will not namespace them (we’ll discuss that more later in the tutorial).

Now we can switch projects:

```bash
lxc project switch client-website
```

Let’s check that we have switched to the new empty project:

```bash
lxc ls
```

We would expect to see an empty list at this point.

## Creating containers in our project
Now that we have an empty project, we can go ahead and create our two containers (the web server and the database server).

```bash
lxc launch ubuntu:26.04 webserver
lxc launch ubuntu:26.04 dbserver
```

Lets check that the containers are running:

```bash
lxc ls
```

We should expect to see output similar to this:

```none
+----------------+---------+------------------------+-------------------------------------------------+-----------------+-----------+
|      NAME      |  STATE  |          IPV4          |                      IPV6                       |      TYPE       | SNAPSHOTS |
+----------------+---------+------------------------+-------------------------------------------------+-----------------+-----------+
| dbserver       | RUNNING | 10.98.212.207 (eth0)   |                                                 | CONTAINER       | 0         |
+----------------+---------+------------------------+-------------------------------------------------+-----------------+-----------+
| webserver      | RUNNING | 10.98.212.167 (eth0)   | fd42:4e0:e708:54de:1c24:d709:b103:72cb (eth0)   | CONTAINER       | 0         |
+----------------+---------+------------------------+-------------------------------------------------+-----------------+-----------+
```

## Listing projects

Sometimes you don’t know which project you want to work in, so LXD allows you to list the projects we have:

```bash
lxc project ls
```

You should see output that looks like this:

```none
+--------------------------+--------+----------+-----------------+-----------------+----------+---------------+---------------------+---------+
|           NAME           | IMAGES | PROFILES | STORAGE VOLUMES | STORAGE BUCKETS | NETWORKS | NETWORK ZONES |     DESCRIPTION     | USED BY |
+--------------------------+--------+----------+-----------------+-----------------+----------+---------------+---------------------+---------+
| client-website (current) | NO     | NO       | YES             | YES             | NO       | NO            |                     | 4       |
+--------------------------+--------+----------+-----------------+-----------------+----------+---------------+---------------------+---------+
| default                  | YES    | YES      | YES             | YES             | YES      | YES           | Default LXD project | 8       |
+--------------------------+--------+----------+-----------------+-----------------+----------+---------------+---------------------+---------+
```

By default, `lxc` commands affect the current project, which is the project with `(current)` after its name.
The `default` project is the project that LXD uses for resources (such as containers, profiles, and images) that do not belong to any other project.

## Listing containers in a project

At this point lets reflect on how our project behaves in relation to the other projects by experimenting with the ways that we can list instances.

Let’s switch back to the default project (this is the project that LXD uses normally), and create a new container:

```bash
lxc project switch default
lxc launch ubuntu:26.04 webserver
```

You'll encounter an error message:

```none
TODO
```

Since we created `client-website` with `{config:option}`project-features:features.profiles` set to `false`, both projects use the same profile with the same bridged network, `lxdbr0`.
This means that we can create instances with the same name, one in each project, but they cannot be running at the same time.

Let's list instances in the current `default` project:

```bash
lxc ls
```

You should expect to see a list of instances that includes the stopped `webcontainer` we just created.
You should *not* see the two `client-website` containers we created earlier.

```none
+---------------+---------+----------------------+-----------------------------------------------+-----------+-----------+
|     NAME      |  STATE  |         IPV4         |                     IPV6                      |   TYPE    | SNAPSHOTS |
+---------------+---------+----------------------+-----------------------------------------------+-----------+-----------+
| new-container | RUNNING | 10.176.69.184 (eth0) | fd42:f773:f0bd:df9f:216:3eff:fec5:3e88 (eth0) | CONTAINER | 0         |
+---------------+---------+----------------------+-----------------------------------------------+-----------+-----------+
```

Now let's list the instances in our `client-website` project, but without switching into it:

```bash
lxc ls --project client-website
```

You should see the `dbserver` and `webserver` containers:

TODO

You can see that we have two containers named `webserver` inside different projects, but, due to the shared profile, they cannot be running at the same time.
Next, we will create a more isolated project in which we can run an instance with the same name as an instanc in another project.

## Creating further isolated projects

So far we have seen how a project can be used to organize instances.
However both the `default` and `client-website` projects shared the same profiles and image libraries.
This means that the `default` profile in the `client-website` project is the same as the `default` profile in the `default` project.
But there are scenarios in which we may want to further isolate a project such that it does not share profiles or image names.

### A new client project

Lets imagine we have now taken on a new client and we need to create a new project for them.
However this client requires a different network configuration than the previous client required.

We could create a new global profile called `client2-default` with the required networking configuration and then assign that profile to the instances in this new project.

However this would mean that the `client2-default` profile would be accessible to all instances that shared the `default` project (including our previously created `client-website` project).
This would be confusing.

Instead, lets create a new project called `client2-website`, but this time we won't set {config:option}`project-features:features.images` or {config:option}`project-features:features.profiles` to `false`.

```bash
lxc project create client2-website
```

Now lets create a container in the new project.
We can use the `--project` flag to create a resource in the specified project, even when another project is "current."

```
lxc launch ubuntu:26.04 webserver --project client2-website
```

Oops! Something went wrong though, you will get this output:

```bash
Creating webserver
Error: Failed container creation: Create container: Create LXC container: Invalid devices: Detect root disk device: No root device could be found
```

Continue to the next step to find out what is going wrong!

## Setting up a new project profile

In the previous step we created a new isolated project and then tried to create a new container inside it.
Unfortunately we were unable to because we got a `No root device could be found` error.
This is because the `default` profile within the new project has not been configured yet.
Let's do so now.

### Comparing profiles

We can compare the `default` and `client2-website` profiles.
First, let's look at the `default` profile in the `default` project.

We can use the `--project` flag again, to specify the `default` project.

```{terminal}
lxc profile show default --project default

name: default
description: Default LXD profile
config: {}
devices:
  eth0:
    name: eth0
    network: lxdbr0
    type: nic
  root:
    path: /
    pool: default
    type: disk
used_by:
- /1.0/instances/webserver?project=client-website
- /1.0/instances/dbserver?project=client-website
- /1.0/instances/new-container
project: default
```

Now let's look at the `default` profile in the `client2-website` project:

Use the `--project` flag again:

```{terminal}
lxc profile show default --project client2-website

name: default
description: Default LXD profile for project client2-website
config: {}
devices: {}
used_by: []
project: client2-website
```

We can see that the missing configuration is for the devices section, specifically the `nic` and `disk` devices.

### Creating the disk device

Lets add a `root` disk device sharing the global `default` storage pool:

```bash
lxc profile device add default root disk path=/ pool=default --project client2-website
```

### Creating the NIC device

Next we can add an `eth0` NIC device to the default profile.
To demonstrate that we can use different `default` profiles in different projects, let's also change the networking configuration for this NIC device to `p2p` rather than the `bridged`.

```bash
lxc profile device add default eth0 nic name=eth0 nictype=p2p --project client2-website
```

### Create the containers
Now let's try again to create the containers for this project.

```
lxc launch ubuntu:26.04 webserver --project client2-website
lxc launch ubuntu:26.04 dbserver --project client2-website
```

And check that they are created:

```{terminal}
lxc ls --project client2-website

+-----------+---------+------+------+-----------+-----------+
|   NAME    |  STATE  | IPV4 | IPV6 |   TYPE    | SNAPSHOTS |
+-----------+---------+------+------+-----------+-----------+
| dbserver  | RUNNING |      |      | CONTAINER | 0         |
+-----------+---------+------+------+-----------+-----------+
| webserver | RUNNING |      |      | CONTAINER | 0         |
+-----------+---------+------+------+-----------+-----------+
```

## Moving containers between projects

So far we have seen how instances can be grouped together and isolated to varying levels.
The last feature we can explore is how to move an instance from one project to another.
Lets move `dbserver` from the `client-website` project into the `client2-website` project.
First we need to stop the container:

```bash
lxc stop dbserver --project client-website
```

Now we can try to move it:

```bash
lxc move dbserver dbserver --project client-website --target-project client2-website
```

But we have got an error again:

```bash
Error: Migration operation failure: Failed creating instance record: Instance "dbserver" already exists
```

This is because you cannot have two instances with the same name in the same project, and we already have a container named `dbserver` in the `client2-website` project.

There are two courses of action here: either delete the existing `dbserver` instance, or move the instance into the project using a different name.
We’ll choose the latter option in this tutorial.

```bash
lxc move dbserver dbserver2 --project client-website --target-project client2-website
```

Now let's confirm that the container has been moved:

```{terminal}
lxc ls --project client2-website

+-----------+---------+------+------+-----------+-----------+
|   NAME    |  STATE  | IPV4 | IPV6 |   TYPE    | SNAPSHOTS |
+-----------+---------+------+------+-----------+-----------+
| dbserver  | RUNNING |      |      | CONTAINER | 0         |
+-----------+---------+------+------+-----------+-----------+
| dbserver2 | STOPPED |      |      | CONTAINER | 0         |
+-----------+---------+------+------+-----------+-----------+
| webserver | RUNNING |      |      | CONTAINER | 0         |
+-----------+---------+------+------+-----------+-----------+
```

## Cleaning up

As a final task, lets clean up the instances and projects we created.

We cannot remove a project that is in use, so we need to remove the instances and images first.

Let's delete the instances in the `client2-website` project:

```bash
lxc delete dbserver -f --project client2-website
lxc delete dbserver2 -f --project client2-website
lxc delete webserver -f --project client2-website
```

We also need to delete any images created in the project:

```bash
lxc image list --project client2-website
```

For each image do:

```bash
lxc image delete <fingerprint> --project client2-website
```

Then delete the project:

```bash
lxc project delete client2-website
```

You can also use the `--force` flag to delete a project:

```bash
lxc project delete client-website --force
```

This also deletes the instances in the `client-website` project.
However, because we created `client-website` with {config:option}`project-features:features.images` set to `false`, the project used images and from the `default` project; as a result, the images were not deleted.

(tutorial-projects-next)=
## Next steps

Now that you've completed your first steps with LXD, you have a general idea of how LXD works.
Next, read up on important concepts in the {ref}`explanation` section and check out more advanced use cases in our {ref}`howtos`.
You can also find a wealth of information in the {ref}`reference` section, including the {doc}`../api`.
