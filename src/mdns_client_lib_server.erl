%%%-------------------------------------------------------------------
%%% @author Heinz Nikolaus Gies <heinz@licenser.net>
%%% @copyright (C) 2012, Heinz Nikolaus Gies
%%% @doc
%%%
%%% @end
%%% Created : 19 Aug 2012 by Heinz Nikolaus Gies <heinz@licenser.net>
%%%-------------------------------------------------------------------
-module(mdns_client_lib_server).

-behaviour(gen_server).

%% API
-export([start_link/1,
         call/2,
         call/3,
         cast/2,
         sure_cast/2,
         stream/4,
         add_endpoint/3,
         downvote_endpoint/2,
         downvote_endpoint/3,
         remove_endpoint/2,
         get_server/1,
         servers/1]).

%% gen_server callbacks
-export([init/1,
         handle_call/3,
         handle_cast/2,
         handle_info/2,
         terminate/2,
         code_change/3]).

-record(state, {
          servers = [],
          service,
          max_downvotes
         }).

-type mdns_server_name() :: string().
-type mdns_server_options() :: [{Name::atom(), Value::binary()}].
-type mdns_server() ::
        {{Server::mdns_server_name(), Options::mdns_server_options()},
         IPS::inet:ip_address() | inet:hostname(),
         IPort::inet:port_number()}.


%%%===================================================================
%%% API
%%%===================================================================

-spec add_endpoint(pid(), mdns_server_name(), mdns_server_options()) -> ok.

add_endpoint(Pid, Server, Options) ->
    gen_server:cast(Pid, {add, Server, Options}).


-spec remove_endpoint(pid(), {mdns_server_name(), mdns_server_options()}) -> ok.
remove_endpoint(Pid, ID) ->
    gen_server:cast(Pid, {remove, ID}).

-spec downvote_endpoint(pid(), atom(), pos_integer()) -> ok.

downvote_endpoint(Pid, Name, Ammount) when Ammount >= 1->
    gen_server:cast(Pid, {downvote, Name, Ammount}).

-spec downvote_endpoint(pid(), atom()) -> ok.

downvote_endpoint(Pid, Name) ->
    downvote_endpoint(Pid, Name, 1).

-spec servers(pid()) -> [mdns_server()].

servers(Pid) ->
    gen_server:call(Pid, servers).

-spec call(pid(), Message::term()) ->
                  pong |
                  {error, no_servers} |
                  {reply, Reply::term()} |
                  noreply.
call(Pid, Message) ->
    gen_server:call(Pid, {call, Message}).

-spec call(pid(), Message::term(), Timeout :: pos_integer() | infinity) ->
                  pong |
                  {error, no_servers} |
                  {reply, Reply::term()} |
                  noreply.
call(Pid, Message, Timeout) ->
    gen_server:call(Pid, {call, Message, Timeout}).

-spec cast(pid(), Message::term()) ->
                  ok.

cast(Pid, Message) ->
    gen_server:cast(Pid, {cast, Message}).

-spec sure_cast(pid(), Message::term()) ->
                       ok.

sure_cast(Pid, Message) ->
    gen_server:cast(Pid, {sure_cast, Message}).

-spec stream(pid(), Message::tuple(),
             StreamFn :: fun((term()) -> _),
             Timeout :: pos_integer() | infinity) ->
    {ok, term()} |
    {error, term()} |
    {error, no_servers}.

stream(Pid, Message, StreamFn, Timeout) ->
    gen_server:call(Pid, {stream, Message, StreamFn, Timeout}).

-spec get_server(pid()) ->
                        {ok, mdns_server()} |
                        {error, no_servers}.


get_server(Pid) ->
    gen_server:call(Pid, get_server).


%%--------------------------------------------------------------------
%% @doc
%% Starts the server
%%
%% @spec start_link(Service) -> {ok, Pid} | ignore | {error, Error}
%% @end
%%--------------------------------------------------------------------
start_link(Service) ->
    gen_server:start_link(?MODULE, [Service], []).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Initializes the server
%%
%% @spec init(Args) -> {ok, State} |
%%                     {ok, State, Timeout} |
%%                     ignore |
%%                     {stop, Reason}
%% @end
%%--------------------------------------------------------------------
init([Service]) ->
    process_flag(trap_exit, true),
    Type = "_" ++ Service ++ "._tcp",
    mdns_client:add_type("_" ++ Service ++ "._tcp"),
    ok = mdns_node_discovery_event:add_handler(
           mdns_client_lib_mdns_handler,
           [list_to_binary(Type), self()]),
    {ok, MaxDownvotes} = application:get_env(max_downvotes),
    {ok, #state{
            service = Service,
            max_downvotes = MaxDownvotes
           }}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling call messages
%%
%% @spec handle_call(Request, From, State) ->
%%                                   {reply, Reply, State} |
%%                                   {reply, Reply, State, Timeout} |
%%                                   {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, Reply, State} |
%%                                   {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------

handle_call(get_server, _From, State = #state{servers = []}) ->
    {reply, {error, no_servers}, State};

handle_call(get_server, _From, State = #state{servers = Servers}) ->
    N = length(Servers),
    {{_, Options}, _, _} = lists:nth(random:uniform(N), Servers),
    {port, PortB} = lists:keyfind(port, 1, Options),
    {ip, IPB} = lists:keyfind(ip, 1, Options),
    {reply,
     {ok, binary_to_list(IPB),
      list_to_integer(binary_to_list(PortB))},
     State};

handle_call(service, _From, State = #state{service = Service}) ->
    {reply, {ok, Service}, State};

handle_call(servers, _From, #state{servers = Servers} = State) ->
    {reply, Servers, State};

handle_call({call, _Message}, _From,
            State = #state{servers = []}) ->
    {reply, {error, no_servers}, State};

handle_call({call, Message}, From,
            State = #state{service = Service}) ->
    mdns_client_lib_call_fsm:call(Service, self(), Message, From),
    {noreply, State};

handle_call({call, Message, Timeout}, From,
            State = #state{service = Service}) ->
    mdns_client_lib_call_fsm:call(Service, self(), Message, From, Timeout),
    {noreply, State};

handle_call({stream, Message, StreamFn, Timeout}, From,
            State = #state{service = Service}) ->
    mdns_client_lib_call_fsm:stream(Service, self(), Message, From, StreamFn,
                                    Timeout),
    {noreply, State};

handle_call(_Request, _From, State) ->
    Reply = ok,
    {reply, Reply, State}.


%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling cast messages
%%
%% @spec handle_cast(Msg, State) -> {noreply, State} |
%%                                  {noreply, State, Timeout} |
%%                                  {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------


default_env(Key, Dflt) ->
    case application:get_env(Key) of
        {ok, V} ->
            V;
        _ ->
            Dflt
    end.

addpool(Service, Name, IP, Port) ->
    PoolConfig = [{name, Name},
                  {group, list_to_atom(Service)},
                  {max_count, default_env(pool_max, 5)},
                  {init_count, default_env(pool_initial, 2)},
                  {start_mfa,
                   {mdns_client_lib_worker,
                    start_link, [Name, IP, Port, self()]}}],
    lager:info("[mdns_client_lib] Creating new pool ~p in group ~s.",
               [Name, Service]),
    pooler:new_pool(PoolConfig).

handle_cast({add, Server, Options},
            #state{servers = Servers,
                   service = Service} = State) ->

    {ip, IP} = lists:keyfind(ip, 1, Options),
    {port, Port} = lists:keyfind(port, 1, Options),
    IPort = list_to_integer(binary_to_list(Port)),
    IPS = binary_to_list(IP),
    Name = list_to_atom(Service ++ "@" ++ IPS ++ ":" ++ binary_to_list(Port)),
    case lists:keyfind({Server, Options}, 1, Servers) of
        false ->
            lager:debug("[mdns_client_lib:~s/~p] Is not know, adding it.",
                        [Service, Name]),
            case Servers of
                [] ->
                    lager:debug("[mdns_client_lib:~s] First endpoint.",
                                [Service]),
                    mdns_client_lib_connection_event:notify_connect(Service);
                _ ->
                    ok
            end,
            addpool(Service, Name, IPS, IPort),
            {noreply,
             State#state{servers=[{{Server, Options}, Name, 0} | Servers]}};
        _ ->
            S1 = [case S of
                      {Opts, N, 0} when N =:= Name ->
                          {Opts, N, 0};
                      {Opts, N, Old} when N =:= Name ->
                          lager:debug("[mdns_client_lib:~s/~p] "
                                      "Known, resetting downvotes ~p->0.",
                                      [Service, Name, Old]),
                          {Opts, N, 0};
                      _ ->
                          S
                  end || S <- Servers],
            {noreply, State#state{servers=S1}}
    end;

handle_cast({cast, _Message}, #state{servers = []} = State) ->
    {noreply, State};

handle_cast({cast, Message}, #state{service = Service} = State) ->
    mdns_client_lib_call_fsm:cast(Service, self(), Message),
    {noreply, State};

handle_cast({sure_cast, Message},
            #state{service = Service} = State) ->
    mdns_client_lib_call_fsm:sure_cast(Service, self(), Message),
    {noreply, State};

handle_cast({downvote, BadName, Amount},
            #state{service = Service,
                   servers = Servers,
                   max_downvotes = MaxDVs} = State) ->
    S1 = [case S of
              {Opts, Name, Cnt} when
                    Name =:= BadName,
                    (Cnt + Amount) >= MaxDVs ->
                  NewCnt = Cnt + Amount,
                  lager:warning("[mdns_client_lib:~p] Removing endpoint "
                                "for too many downvotes (~p/~p).",
                                [BadName, NewCnt, MaxDVs]),
                  pooler:rm_pool(BadName),
                  {Opts, Name, NewCnt};
              {Opts, Name, Cnt} when Name =:= BadName ->
                  NewCnt = Cnt + Amount,
                  lager:warning("[mdns_client_lib:~s/~p] "
                                "downvoted by ~p to ~p.",
                                [Service, BadName, Amount, NewCnt]),
                  {Opts, Name, NewCnt};
              Srv ->
                  Srv
          end || S <- Servers],
    S2 = [S || S = {_, _, Cnt} <- S1, Cnt < MaxDVs],
    {noreply, State#state{servers = S2}};

handle_cast({remove, BadID}, #state{service = Service,
                                    servers = Servers} = State) ->
    [begin
         lager:warning("[mdns_client_lib:~s/~s] Removing endpoint by force.",
                       [Service, Pool]),
         pooler:rm_pool(Pool)
     end || {ID, Pool, _} <- Servers, ID =:= BadID],
    S2 = [S || S = {ID, _, _} <- Servers, ID =/= BadID],
    {noreply, State#state{servers = S2}};

handle_cast(_Msg, State) ->
    {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling all non call/cast messages
%%
%% @spec handle_info(Info, State) -> {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_info(_Info, State) ->
    {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any
%% necessary cleaning up. When it returns, the gen_server terminates
%% with Reason. The return value is ignored.
%%
%% @spec terminate(Reason, State) -> void()
%% @end
%%--------------------------------------------------------------------
terminate(_Reason, #state{servers = Servers}) ->
    [pooler:rm_pool(Name) || {_, Name, _} <- Servers],
    ok.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Convert process state when code is changed
%%
%% @spec code_change(OldVsn, State, Extra) -> {ok, NewState}
%% @end
%%--------------------------------------------------------------------
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================
