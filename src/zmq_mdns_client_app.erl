-module(zmq_mdns_client_app).

-behaviour(application).

%% Application callbacks
-export([start/2, stop/1]).

%% ===================================================================
%% Application callbacks
%% ===================================================================

start(_StartType, _StartArgs) ->
    {ok, Domain} = application:get_env(zmq_mdns_client, domain),
    MDNSConfig = [{port, 5353},
		  {address, {224, 0, 0, 251}},
		  {domain, Domain},
		  {types, []}],
    {ok, _} =  mdns_client_supervisor:start_link([MDNSConfig]),
    zmq_mdns_client_main_sup:start_link().

stop(_State) ->
    ok.
