# Erlang node discovery #

Allows to organize Erlang/Elixir node discovery using the information
about nodes provided in config. Useful in cases when your Erlang/Elixir nodes can be started/re-started
on different hosts, as it happens in Mesos.


## Basic configuration ##

```
[
    {erlang_node_discovery, [
        {db_callback, erlang_node_discovery_db},
        % List of {node, host, port}
        {node_host_port, [
            {app1, host1.local, 17011},
            {app2, host2.local, 17012},
            {app3, host3.local, 17013}
        ]}
    ]}
].
```


## Using the application with EPMDLESS ##

It might be useful for cases when you want to organize a service discovery and don't want to relay on
standard distribution protocol. See more details about EPMDLESS here: https://github.com/oltarasenko/epmdless



```
{ erlang_node_discovery, [
    {db_callback, epmdless_dist},
    {node_host_port, [
        {app1, host1.local, 17011},
        {app2, host2.local, 17012},
        {app3, host3.local, 17013}
    ]},
    {cookie, app_cookie}
]}
  ```