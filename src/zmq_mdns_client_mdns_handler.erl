-module(zmq_mdns_client_mdns_handler).

-behaviour(gen_event).

-export([init/1,
	 terminate/2,
	 handle_info/2,
	 handle_event/2,
	 code_change/3,
	 handle_call/2]).

init(_) ->
    {ok, stateless}.

terminate(remove_handler, _) ->
    ok;

terminate(stop, _) ->
    ok;

terminate(Error, State) ->
    error_logger:error_report([{module, ?MODULE},
			       {self, self()},
			       {error, Error},
			       {state, State}]).

handle_event({service_add, _Type, Host, Options}, State) ->
    io:format("Service add: ~p (~p)~n" , [Host, Options]),
    zmq_mdns_client_server:add_endpoint(Host, Options),
    {ok, State};

handle_event({service_remove, _Type, Host}, State) ->
    io:format("Service remove: ~p~n" , [Host]),
    zmq_mdns_client_server:remove_endpoint(Host),
    {ok, State}.

handle_info({'EXIT', _, shutdown}, _) ->
    remove_handler.

code_change(_,_, State) ->
    {ok, State}.
		   
handle_call(_, State) ->
    {ok, State}.
