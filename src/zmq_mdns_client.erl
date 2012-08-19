-module(zmq_mdns_client).

-export([start/0]).


start() ->
    application:start(zmq_mdns_client).
