# Node discovery #

Allows Erlang node discovery using Redis pub-sub with epmdless.

## Configuration ##
An example:

```erl
{erlang_node_discovery,
    [{pub_interval, 15000},
     {container_name, "CONTAINER_NAME"},
     {channel_prefix, "node_info_channel_"},
     {redis_cluster, node_discovery},
     {discovery_port, 17010},
     {db_callback, epmdless_dist}]}
```

db_callback
-----------
Database callback module for node discovery service.

discovery_port
--------------
The port number for discovery service.

It is the epmdless distribution port.

redis_cluster
-------------
Redis cluster config for discovery service.

It should match one configuration in redis_config.

channel_prefix
--------------
The pub-sub channel prefix for discovery service.

It will be published to the redis channel as identify for the cluster.

container_name
--------------
The environment variable for container name.

It will be published to the redis channel as identify for the node.

pub_interval
------------
The publish time interval, in milliseconds.

A node will publish its info to the redis channel when it's not in a cluster.

