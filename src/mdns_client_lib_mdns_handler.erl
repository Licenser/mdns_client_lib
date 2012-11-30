-module(mdns_client_lib_mdns_handler).

-behaviour(gen_event).

-export([init/1,
	 terminate/2,
	 handle_info/2,
	 handle_event/2,
	 code_change/3,
	 handle_call/2]).

init([Type, Pid]) ->
    {ok, {Type, Pid}}.

terminate(remove_handler, _) ->
    ok;

terminate(stop, _) ->
    ok;

terminate(Error, State) ->
    error_logger:error_report([{module, ?MODULE},
			       {self, self()},
			       {error, Error},
			       {state, State}]).

handle_event({service_add, Type, Host, Options}, {Type, Pid}) ->
    mdns_client_lib_server:add_endpoint(Pid, Host, Options),
    {ok, {Type, Pid}};

handle_event({service_remove, Type, Host, Options}, {Type, Pid}) ->
    mdns_client_lib_server:remove_endpoint(Pid, {Host, Options}),
    {ok, {Type, Pid}};

handle_event(_, State) ->
    {ok, State}.

handle_info({'EXIT', _, shutdown}, _) ->
    remove_handler.

code_change(_, _, State) ->
    {ok, State}.


handle_call(_, State) ->
    {ok, ok, State}.
