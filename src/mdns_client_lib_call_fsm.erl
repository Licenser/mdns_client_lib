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
         call/5,
         stream/7,
         cast/3,
         sure_cast/3,
         start_link/6
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
         test_worker/2,
         do/2
        ]).

-define(SERVER, ?MODULE).
-record(state, {service, handler, command, from, socket, type, retry = 0,
                worker, max_retries, retry_delay, timeout}).

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

start_link(Service, Handler, Command, From, Timeout, Type) ->
    gen_fsm:start_link(?MODULE,
                       [list_to_atom(Service), Handler, Command,
                        From, Timeout, Type], []).

call(Service, Handler, Command, From) ->
    supervisor:start_child(
      mdns_client_lib_call_fsm_sup,
      [Service, Handler, Command, From, undefined, call]).

call(Service, Handler, Command, From, Timeout) ->
    supervisor:start_child(mdns_client_lib_call_fsm_sup,
                           [Service, Handler, Command, From, Timeout, call]).

stream(Service, Handler, Command, From, StreamFn, Acc0, Timeout) ->
    supervisor:start_child(mdns_client_lib_call_fsm_sup,
                           [Service, Handler, Command, From, Timeout,
                            {stream, StreamFn, Acc0}]).

sure_cast(Service, Handler, Command) ->
    supervisor:start_child(
      mdns_client_lib_call_fsm_sup,
      [Service, Handler, Command, undefined, undefined, sure_cast]).

cast(Service, Handler, Command) ->
    supervisor:start_child(
      mdns_client_lib_call_fsm_sup,
      [Service, Handler, Command, undefined, undefined, cast]).


%%%===================================================================
%%% gen_fsm callbacks
%%%===================================================================

init([Service, Handler, Command, From, InTimeout, Type]) ->
    process_flag(trap_exit, true),
    random:seed(erlang:phash2([node()]),
                erlang:monotonic_time(),
                erlang:unique_integer()),

    {ok, Retries} = application:get_env(max_retries),
    {ok, RetryDelay} = application:get_env(retry_delay),
    Timeout = case {InTimeout, application:get_env(recv_timeout)} of
                  {undefined, {ok, T}} ->
                      T;
                  {undefined, _} ->
                      1500;
                  {V, _} ->
                      V
              end,
    next(),
    {ok, get_worker, #state{
                        timeout = Timeout,
                        max_retries = Retries,
                        retry_delay = RetryDelay,
                        service = Service,
                        command = Command,
                        handler = Handler,
                        type = Type,
                        from = From
                       }}.

get_worker(_, State = #state{retry = R, max_retries = M})
  when R > M ->
    {stop, {error, no_connection}, State};

get_worker(_, State = #state{service=Service, retry=Retry,
                             worker=undefined, retry_delay = Deleay}) ->
    case pooler:take_group_member(Service) of
        {error_no_group, G} ->
            lager:warning("[MDNS Client:~s] Group ~p does not exist.",
                          [Service, G]),
            next(random:uniform(Deleay)),
            {next_state, get_worker, State#state{retry = Retry + 1}};

        error_no_members ->
            lager:warning("[MDNS Client:~p] Service has no free members.",
                          [Service]),
            next(random:uniform(Deleay)),
            {next_state, get_worker, State#state{retry = Retry + 1}};
        Worker ->
            next(),
            {next_state, test_worker,
             State#state{worker = Worker, retry = Retry + 1}}
    end;

get_worker(_, State = #state{service=Service, worker = Worker}) ->
    pooler:return_group_member(Service, Worker),
    next(),
    {next_state, get_worker, State#state{worker = undefined}}.

test_worker(_, #state{worker = Worker, service=Service} = State) ->
    case gen_server:call(Worker, {call, ping, 500}) of
        {ok, Res} ->
            case binary_to_term(Res) of
                pong ->
                    next(),
                    {next_state, do, State};
                E ->
                    lager:warning("[MDNS Client: ~p] Test for worker failed, "
                                  "no pong returned: ~p.",
                                  [Service, E]),
                    next(),
                    {next_state, get_worker, State}
            end;
        E ->
            lager:warning("[MDNS Client: ~p] Test for worker failed: ~p.",
                          [Service, E]),
            next(),
            {next_state, get_worker, State}
    end.

do(_, #state{from = From, command = Command, worker = Worker,
             timeout = Timeout, type = {stream, StreamFn, Acc0}} = State) ->
    Res = gen_server:call(Worker, {stream, Command, StreamFn, Acc0, Timeout},
                          Timeout),
    gen_server:reply(From, Res),
    {stop, normal, State};

do(_, #state{from = undefined, command = Command, worker = Worker,
             timeout = Timeout} = State) ->
    gen_server:call(Worker, {call, Command, Timeout}, Timeout),
    {stop, normal, State};

do(_, #state{from = From, command = Command, worker = Worker,
             timeout = Timeout} = State) ->
    case gen_server:call(Worker, {call, Command, Timeout}, Timeout) of
        {ok, Res} ->
            gen_server:reply(From, binary_to_term(Res)),
            {stop, normal, State};
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

next(After) ->
    gen_fsm:send_event_after(After, next).

next() ->
    next(0).
