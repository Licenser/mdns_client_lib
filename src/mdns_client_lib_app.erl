-module(mdns_client_lib_app).

-behaviour(application).

%% Application callbacks
-export([start/2, stop/1]).

%% ===================================================================
%% Application callbacks
%% ===================================================================

start(_StartType, _StartArgs) ->
    {ok, Domain} = application:get_env(mdns_client_lib, domain),
    {ok, IFace} = application:get_env(mdns_client_lib, interface),
    {ok, Port} = application:get_env(mdns_client_lib, port),
    {ok, Addr} = application:get_env(mdns_client_lib, address),
    MDNSConfig = [{port, Port},
                  {address, Addr},
                  {domain, Domain},
                  {interface, IFace},
                  {types, []}],
    {ok, _} =  mdns_client_supervisor:start_link([MDNSConfig]),
    mdns_client_lib_main_sup:start_link().

stop(_State) ->
    ok.
