-module(zmq_mdns_client_app).

-behaviour(application).

%% Application callbacks
-export([start/2, stop/1]).

%% ===================================================================
%% Application callbacks
%% ===================================================================

start(_StartType, _StartArgs) ->
    {ok, Domain} = application:get_env(zmq_mdns_client, domain),
    {ok, Service} = application:get_env(zmq_mdns_client, service),
    MDNSConfig = [{port, 5353},
		  {address, {224, 0, 0, 251}},
		  {domain, Domain},
		  {types, ["_" ++ Service ++ "._zeromq._tcp"]}],
    io:format("mDNS Configuration: ~p.~n", [MDNSConfig]),
    {ok, _} =  mdns_client_supervisor:start_link([MDNSConfig]),
    ok = mdns_node_discovery_event:add_handler(zmq_mdns_client_mdns_handler),
    zmq_mdns_client_sup:start_link().

stop(_State) ->
    ok.
