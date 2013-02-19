%%%-------------------------------------------------------------------
%%% @author Heinz Nikolaus Gies <heinz@licenser.net>
%%% @copyright (C) 2012, Heinz Nikolaus Gies
%%% @doc
%%%
%%% @end
%%% Created :  6 Oct 2012 by Heinz Nikolaus Gies <heinz@licenser.net>
%%%-------------------------------------------------------------------
-module(mdns_client_lib_call_fsm).

-behaviour(gen_fsm).

%% API
-export([
         call/4,
         cast/3,
         sure_cast/3,
         start_link/5
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
         returning_server/2,
         new_server/2
        ]).

-define(SERVER, ?MODULE).

-record(state, {server, handler, command, from, socket, type}).

%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% Creates a gen_fsm process which calls Module:init/1 to
%% initialize. To ensure a synchronized start-up procedure, this
%% function does not return until Module:init/1 has returned.
%%
%% @spec start_link(Server, Handler, Command, From) -> {ok, Pid}
%%                                                   | ignore
%%                                                   | {error, Error}
%% @end
%%--------------------------------------------------------------------

start_link(Server, Handler, Command, From, Type) ->
    gen_fsm:start_link(?MODULE, [Server, Handler, Command, From, Type], []).

call(Server, Handler, Command, From) ->
    supervisor:start_child(mdns_client_lib_call_fsm_sup, [Server, Handler, Command, From, call]).

sure_cast(Server, Handler, Command) ->
    supervisor:start_child(mdns_client_lib_call_fsm_sup, [Server, Handler, Command, undefined, sure_cast]).

cast(Server, Handler, Command) ->
    supervisor:start_child(mdns_client_lib_call_fsm_sup, [Server, Handler, Command, undefined, cast]).


%%%===================================================================
%%% gen_fsm callbacks
%%%===================================================================

init([undefined, Handler, Command, From, Type]) ->
    {ok, new_server, #state{
           command = Command,
           handler = Handler,
           type = Type,
           from = From}, 0};

init([Server, Handler, Command, From, Type]) ->
    {ok, connecting, #state{
           server = Server,
           command = Command,
           handler = Handler,
           type = Type,
           from = From}, 0}.

connecting(_Event, #state{server={_Spec, IP, Port}} = State) ->
    case gen_tcp:connect(IP, Port, [binary, {active,false}, {packet,4}], 100) of
        {ok, Socket} ->
            {next_state, sending, State#state{socket = Socket}, 0};
        _ ->
            {next_state, returning_server, State, 0}
    end.

sending(_Event, #state{socket=Socket,
                       command = Command} = State) ->
    case gen_tcp:send(Socket, term_to_binary(Command)) of
        ok ->
            {next_state, rcving, State, 0};
        _ ->
            {next_state, returning_server, State, 0}
    end.


rcving(_Event, #state{socket=Socket, from=undefined} = State) ->
    case gen_tcp:recv(Socket, 0) of
        {ok, _Res} ->
            {next_state, closing, State, 0};
        _ ->
            {next_state, returning_server, State, 0}
    end;

rcving(_Event, #state{socket=Socket, from=From} = State) ->
    case gen_tcp:recv(Socket, 0) of
        {ok, Res} ->
            gen_server:reply(From, binary_to_term(Res)),
            {next_state, closing, State, 0};
        _ ->
            {next_state, returning_server, State, 0}
    end.

closing(_Event, #state{socket=Socket} = State) ->
    gen_tcp:close(Socket),
    {stop, normal, State}.

returning_server(_Event, #state{
                   server={Spec, _, _},
                   handler = Handler
                  } = State) ->
    mdns_client_lib_server:remove_endpoint(Handler, Spec),
    {next_state, new_server, State, 0}.

new_server(_Event, #state{
             handler = Handler,
             type = sure_cast
            } = State) ->
    case mdns_client_lib_server:get_server(Handler) of
        {ok, Server} ->
            {next_state, connecting, State#state{server=Server}, 0} ;
        _ ->
            {next_state, new_server, State, 1000}
    end;

new_server(_Event, #state{
             type = cast
            } = State) ->
    {stop, normal, State};

new_server(_Event, #state{
             handler = Handler,
             from = From
            } = State) ->
    case {From, mdns_client_lib_server:get_server(Handler)} of
        {_, {ok, Server}} ->
            {next_state, connecting, State#state{server=Server}, 0} ;
        {undefined, _} ->
            {stop, normal, State};
        _ ->
            gen_server:reply(From, {error, no_servers}),
            {stop, normal, State}
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
