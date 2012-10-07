-module(mdns_client_lib).

-export([start/0,
	 instance/1,
	 call/2,
	 cast/2,
	 servers/1
	]).

call(Pid, Msg) ->
    mdns_client_lib_server:call(Pid, Msg).

cast(Pid, Msg) ->
    mdns_client_lib_server:cast(Pid, Msg).

instance(Service) ->
    supervisor:start_child(mdns_client_lib_sup, [Service]).

servers(Pid) ->
    mdns_client_lib_server:servers(Pid).

start() ->
    application:start(mdns_client_lib).
