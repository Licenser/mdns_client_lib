-module(zmq_mdns_client).

-export([start/0,
	 instance/1,
	 send/2,
	 register_on_connect/2,
	 register_on_disconnect/2
	]).

send(Pid, Msg) ->
    zmq_mdns_client_server:send(Pid, Msg).

register_on_connect(Pid, Fn) ->
    zmq_mdns_client_server:register_on_connect(Pid, Fn).

register_on_disconnect(Pid, Fn) ->
    zmq_mdns_client_server:register_on_disconnect(Pid, Fn).

instance(Service) ->
    supervisor:start_child(zmq_mdns_client_sup, [Service]).

start() ->
    application:start(zmq_mdns_client).
