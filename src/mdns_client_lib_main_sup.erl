-module(mdns_client_lib_main_sup).

-behaviour(supervisor).

%% API
-export([start_link/0]).

%% Supervisor callbacks
-export([init/1]).

%% ===================================================================
%% API functions
%% ===================================================================

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

%% ===================================================================
%% Supervisor callbacks
%% ===================================================================

init([]) ->
    {ok,
     {{one_for_one, 5, 10},
      [{mdns_client_lib_sup,
        {mdns_client_lib_sup, start_link, []},
        permanent, 5000, supervisor, [mdns_client_lib_sup]},
       {mdns_client_lib_connection_responder,
        {gen_event, start_link, [{local, mdns_client_lib_connection_event}]},
        permanent, 5000, worker, []},
       {mdns_client_lib_call_fsm_sup,
        {mdns_client_lib_call_fsm_sup, start_link, []},
        permanent, 5000, supervisor, [mdns_client_lib_call_fsm_sup]}]}}.
