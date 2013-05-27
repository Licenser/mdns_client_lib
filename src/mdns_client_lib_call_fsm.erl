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
         get_worker/2,
         do/2
        ]).

-define(SERVER, ?MODULE).
-define(RETRY_DELAY, 150).
-define(RETRIES, 10).
-record(state, {service, handler, command, from, socket, type, retry = 0, worker}).

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

start_link(Service, Handler, Command, From, Type) ->
    gen_fsm:start_link(?MODULE, [list_to_atom(Service), Handler, Command, From, Type], []).

call(Service, Handler, Command, From) ->
    supervisor:start_child(mdns_client_lib_call_fsm_sup, [Service, Handler, Command, From, call]).

sure_cast(Service, Handler, Command) ->
    supervisor:start_child(mdns_client_lib_call_fsm_sup, [Service, Handler, Command, undefined, sure_cast]).

cast(Service, Handler, Command) ->
    supervisor:start_child(mdns_client_lib_call_fsm_sup, [Service, Handler, Command, undefined, cast]).


%%%===================================================================
%%% gen_fsm callbacks
%%%===================================================================

init([Service, Handler, Command, From, Type]) ->
    process_flag(trap_exit, true),
    random:seed(now()),
    {ok, get_worker, #state{
                service = Service,
                command = Command,
                handler = Handler,
                type = Type,
                from = From
               }, 0}.


get_worker(_, State = #state{retry=Retry}) when Retry > ?RETRIES ->
    {stop, {error, no_connection}, State};

get_worker(_, State = #state{service=Service, retry=Retry, worker=undefined}) ->
    case pooler:take_group_member(Service) of
        {error_no_group, G} ->
            lager:warning("[MDNS Cleint] Group ~p:~p does not exist.",
                          [Service, G]),
            {next_state, get_worker, State#state{retry = Retry + 1},
             random:uniform(?RETRY_DELAY)};
        error_no_members ->
            lager:warning("[MDNS Cleint] Service ~p has no free members.",
                          [Service]),
            {next_state, get_worker, State#state{retry = Retry + 1},
             random:uniform(?RETRY_DELAY)};
        Worker ->
            {next_state, do, State#state{worker = Worker, retry = Retry + 1}, 0}
    end;
get_worker(_, State = #state{service=Service, worker = Worker}) ->
    pooler:return_group_member(Service, Worker),
    {next_state, get_worker, State#state{worker = undefined}, 0}.


do(_, #state{from = From, command = Command, worker = Worker} = State) ->
    case gen_server:call(Worker, {call, Command}) of
        {ok, Res} ->
            case From of
                undefined ->
                    ok;
                _ ->
                    gen_server:reply(From, binary_to_term(Res))
            end,
            {stop, normal, State};
        {error, E} when E =:= enotconn orelse
                        E =:= closed ->
            {next_state, get_worker, State, 0};
        E ->
            gen_server:reply(From, {error, E}),
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
terminate(normal, _StateName, #state{service = Service,
                                     worker = Worker}) ->
    pooler:return_group_member(Service, Worker),
    ok;
terminate(_Reason, _StateName, _State = #state{worker = undefined,
                                               from = undefined}) ->
    ok;
terminate(_Reason, _StateName, _State = #state{service = Service,
                                               worker = Worker,
                                               from = undefined}) ->
    pooler:return_group_member(Service, Worker),
    ok;
terminate(Reason, _StateName, _State = #state{worker = undefined,
                                              from = From}) ->
    gen_server:reply(From, {error, Reason}),
    ok;
terminate(Reason, _StateName, _State = #state{service = Service,
                                              worker = Worker,
                                              from = From}) ->
    pooler:return_group_member(Service, Worker),
    gen_server:reply(From, {error, Reason}),
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
