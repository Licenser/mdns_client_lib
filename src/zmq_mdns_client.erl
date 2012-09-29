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
    Type = "_" ++ Service ++ "._zeromq._tcp",
    mdns_client:add_type("_" ++ Service ++ "._zeromq._tcp"),
    {ok, Pid} = supervisor:start_child(zmq_mdns_client_sup, []),
    ok = mdns_node_discovery_event:add_handler(
	   zmq_mdns_client_mdns_handler, 
	   [list_to_binary(Type), Pid]),
    {ok, Pid}.

start() ->
    application:start(zmq_mdns_client).
