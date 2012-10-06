%%%-------------------------------------------------------------------
%%% @author Heinz Nikolaus Gies <heinz@licenser.net>
%%% @copyright (C) 2012, Heinz Nikolaus Gies
%%% @doc
%%%
%%% @end
%%% Created :  6 Oct 2012 by Heinz Nikolaus Gies <heinz@licenser.net>
%%%-------------------------------------------------------------------
-module(mdns_call_fsm).

-behaviour(gen_fsm).

%% API
-export([
	 execute/4,
	 start_link/4
	]).

%% gen_fsm callbacks
-export([init/1, 
	 handle_event/3,
	 handle_sync_event/4, 
	 handle_info/3, 
	 terminate/3, 
	 code_change/4]).

-export([
	 connecting/2,
	 sending/2,
	 rcving/2,
	 closing/2,
	 new_server/2
	]).

-define(SERVER, ?MODULE).

-record(state, {server, handler, command, from, socket}).

%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% Creates a gen_fsm process which calls Module:init/1 to
%% initialize. To ensure a synchronized start-up procedure, this
%% function does not return until Module:init/1 has returned.
%%
%% @spec start_link() -> {ok, Pid} | ignore | {error, Error}
%% @end
%%--------------------------------------------------------------------
start_link(Server, Handler, Command, From) ->
    gen_fsm:start_link(?MODULE, [Server, Handler, Command, From], []).

execute(Server, Handler, Command, From) ->
    supervisor:start_child(mdns_call_fsm_sup, [Server, Handler, Command, From]).


%%%===================================================================
%%% gen_fsm callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Whenever a gen_fsm is started using gen_fsm:start/[3,4] or
%% gen_fsm:start_link/[3,4], this function is called by the new
%% process to initialize.
%%
%% @spec init(Args) -> {ok, StateName, State} |
%%                     {ok, StateName, State, Timeout} |
%%                     ignore |
%%                     {stop, StopReason}
%% @end
%%--------------------------------------------------------------------
init([Server, Handler, Command, From]) ->
    {ok, connecting, #state{
	   server = Server,
	   command = Command,
	   handler = Handler,
	   from = From},0}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% There should be one instance of this function for each possible
%% state name. Whenever a gen_fsm receives an event sent using
%% gen_fsm:send_event/2, the instance of this function with the same
%% name as the current state name StateName is called to handle
%% the event. It is also called if a timeout occurs.
%%
%% @spec state_name(Event, State) ->
%%                   {next_state, NextStateName, NextState} |
%%                   {next_state, NextStateName, NextState, Timeout} |
%%                   {stop, Reason, NewState}
%% @end
%%--------------------------------------------------------------------
connecting(_Event, #state{server={_Spec, IP, Port}} = State) ->
    case gen_tcp:connect(IP, Port, [binary, {active,false}]) of
	{ok, Socket} ->
	    {next_state, sending, State#state{socket = Socket}, 0};
	_ ->
	    {next_state, new_server, State}
    end.

sending(_Event, #state{socket=Socket,
		       command = Command} = State) ->
    case gen_tcp:send(Socket, term_to_binary(Command)) of
	ok ->
	    {next_state, rcving, State, 0};
	_ ->
	    {next_state, new_server, State}
    end.

rcving(_Event, #state{socket=Socket, from=From} = State) ->
    case gen_tcp:recv(Socket, 0) of
	{ok, Res} ->
	    gen_server:reply(From, binary_to_term(Res)),
	    {next_state, closing, State, 0};
	_ ->
	    {next_state, new_server, State}
    end.

closing(_Event, #state{socket=Socket} = State) ->
    gen_tcp:close(Socket),
    {stop, normal, State}.

new_server(_Event, #state{
	     server={Spec, _, _},
	     handler = Handler, 
	     from = From
	    } = State) ->
    case zmq_mdns_client_server:server_down(Handler, Spec) of
	{ok, Server} ->
	    {next_state, connecting, State#state{server=Server}, 0} ;
	_ ->
	    gen_server:reply(From, {error, no_servers}),
	    {stop, ok, State}
    end.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Whenever a gen_fsm receives an event sent using
%% gen_fsm:send_all_state_event/2, this function is called to handle
%% the event.
%%
%% @spec handle_event(Event, StateName, State) ->
%%                   {next_state, NextStateName, NextState} |
%%                   {next_state, NextStateName, NextState, Timeout} |
%%                   {stop, Reason, NewState}
%% @end
%%--------------------------------------------------------------------
handle_event(_Event, StateName, State) ->
    {next_state, StateName, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Whenever a gen_fsm receives an event sent using
%% gen_fsm:sync_send_all_state_event/[2,3], this function is called
%% to handle the event.
%%
%% @spec handle_sync_event(Event, From, StateName, State) ->
%%                   {next_state, NextStateName, NextState} |
%%                   {next_state, NextStateName, NextState, Timeout} |
%%                   {reply, Reply, NextStateName, NextState} |
%%                   {reply, Reply, NextStateName, NextState, Timeout} |
%%                   {stop, Reason, NewState} |
%%                   {stop, Reason, Reply, NewState}
%% @end
%%--------------------------------------------------------------------
handle_sync_event(_Event, _From, StateName, State) ->
    Reply = ok,
    {reply, Reply, StateName, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called by a gen_fsm when it receives any
%% message other than a synchronous or asynchronous event
%% (or a system message).
%%
%% @spec handle_info(Info,StateName,State)->
%%                   {next_state, NextStateName, NextState} |
%%                   {next_state, NextStateName, NextState, Timeout} |
%%                   {stop, Reason, NewState}
%% @end
%%--------------------------------------------------------------------
handle_info(_Info, StateName, State) ->
    {next_state, StateName, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called by a gen_fsm when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any
%% necessary cleaning up. When it returns, the gen_fsm terminates with
%% Reason. The return value is ignored.
%%
%% @spec terminate(Reason, StateName, State) -> void()
%% @end
%%--------------------------------------------------------------------
terminate(_Reason, _StateName, _State) ->
    ok.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Convert process state when code is changed
%%
%% @spec code_change(OldVsn, StateName, State, Extra) ->
%%                   {ok, StateName, NewState}
%% @end
%%--------------------------------------------------------------------
code_change(_OldVsn, StateName, State, _Extra) ->
    {ok, StateName, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================
