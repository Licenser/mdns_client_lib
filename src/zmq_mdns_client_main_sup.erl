
-module(zmq_mdns_client_main_sup).

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
    {ok, {{one_for_one, 5, 10}, [{zmq_mdns_client_sup, 
				  {zmq_mdns_client_sup, start_link, []}, 
				  permanent, 5000, supervisor, [zmq_mdns_client_sup]},
				 {zmq_mdns_connection_responder, 
				  {gen_event, start_link, [{local, zmq_mdns_connection_event}]},
				  permanent, 5000, worker, []},
				 {mdns_call_fsm_sup, {mdns_call_fsm_sup, start_link, []},
				  permanent, 5000, supervisor, [mdns_call_fsm_sup]}]}}.

