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
         cast/2,
         sure_cast/2,
         add_endpoint/3,
         remove_endpoint/2,
         remove_endpoint/3,
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
          servers = {[], []},
          service
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

-spec remove_endpoint(pid(), mdns_server_name(), mdns_server_options()) -> ok.

remove_endpoint(Pid, Server, Options) ->
    remove_endpoint(Pid, {Server, Options}).


-spec remove_endpoint(pid(), {mdns_server_name(), mdns_server_options()}) -> ok.

remove_endpoint(Pid, Server) ->
    gen_server:cast(Pid, {remove, Server}).

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

-spec cast(pid(), Message::term()) ->
                  ok.

cast(Pid, Message) ->
    gen_server:cast(Pid, {cast, Message}).

-spec sure_cast(pid(), Message::term()) ->
                       ok.

sure_cast(Pid, Message) ->
    gen_server:cast(Pid, {sure_cast, Message}).

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
    Type = "_" ++ Service ++ "._zeromq._tcp",
    mdns_client:add_type("_" ++ Service ++ "._zeromq._tcp"),
    ok = mdns_node_discovery_event:add_handler(
           mdns_client_lib_mdns_handler,
           [list_to_binary(Type), self()]),
    {ok, #state{service = Service}}.

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

handle_call(servers, _From, #state{servers = {Servers, R}} = State) ->
    {reply, Servers++R, State};

handle_call(get_server, _From, #state{servers = {[], []}} = State) ->
    {reply, {error, no_server}, State#state{servers = {[], []}}};

handle_call(get_server, _From, #state{servers = {[Spec | Servers1], ServersR1}} = State) ->
    {reply, {ok, Spec},
     State#state{servers = {Servers1, [Spec|ServersR1]}}};

handle_call(get_server, _From, #state{servers = {[], [Spec | ServersR1]}} = State) ->
    {reply, {ok, Spec},
     State#state{servers = {ServersR1, [Spec]}}};

handle_call({call, _Message}, _From, #state{servers = {[], []}} = State) ->
    {reply, {error, no_server}, State};

handle_call({call, Message}, From, #state{servers = {[Server|Servers], ServersR}} = State) ->
    mdns_client_lib_call_fsm:call(Server, self(), Message, From),
    {noreply, State#state{servers = {Servers, [Server|ServersR]}}};

handle_call({call, Message}, From, #state{servers = {[], [Server|ServersR]}} = State) ->
    mdns_client_lib_call_fsm:call(Server, self(), Message, From),
    {noreply, State#state{servers = {ServersR, [Server]}}};

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

handle_cast({add, Server, Options},
            #state{servers = {Servers, ServersR},
                   service = Service} = State) ->
    AllServers = Servers++ServersR,
    case lists:keyfind({Server, Options}, 1, AllServers) of
        false ->
            {ip, IP} = lists:keyfind(ip, 1, Options),
            {port, Port} = lists:keyfind(port, 1, Options),
            IPort = list_to_integer(binary_to_list(Port)),
            IPS = binary_to_list(IP),
            case AllServers of
                [] ->
                    mdns_client_lib_connection_event:notify_connect(Service);
                _ ->
                    ok
            end,
            {noreply, State#state{servers={[{{Server, Options}, IPS, IPort} | Servers], ServersR}}};
        _ ->
            {noreply, State}
    end;

handle_cast({cast, _Message}, #state{servers = {[], []}} = State) ->
    {noreply, State};

handle_cast({cast, Message}, #state{servers = {[Server|Servers], ServersR}} = State) ->
    mdns_client_lib_call_fsm:cast(Server, self(), Message),
    {noreply, State#state{servers = {Servers, [Server|ServersR]}}};

handle_cast({cast, Message}, #state{servers = {[], [Server|ServersR]}} = State) ->
    mdns_client_lib_call_fsm:cast(Server, self(), Message),
    {noreply, State#state{servers = {ServersR, [Server]}}};

handle_cast({sure_cast, Message}, #state{servers = {[], []}} = State) ->
    mdns_client_lib_call_fsm:sure_cast(undefined, self(), Message),
    {noreply, State};

handle_cast({sure_cast, Message}, #state{servers = {[Server|Servers], ServersR}} = State) ->
    mdns_client_lib_call_fsm:sure_cast(Server, self(), Message),
    {noreply, State#state{servers = {Servers, [Server|ServersR]}}};

handle_cast({sure_cast, Message}, #state{servers = {[], [Server|ServersR]}} = State) ->
    mdns_client_lib_call_fsm:sure_cast(Server, self(), Message),
    {noreply, State#state{servers = {ServersR, [Server]}}};

handle_cast({remove, _Server},
            #state{servers = {[], []}} = State) ->
    {noreply, State};

handle_cast({remove, Server},
            #state{servers = {[{Server, _, _}], []},
                   service = Service} = State) ->
    mdns_client_lib_connection_event:notify_disconnect(Service),
    {noreply, State#state{servers = {[], []}}};

handle_cast({remove, Server},
            #state{servers = {[], [{Server, _, _}]},
                   service = Service} = State) ->
    mdns_client_lib_connection_event:notify_disconnect(Service),
    {noreply, State#state{servers = {[], []}}};

handle_cast({remove, Server},
            #state{servers = {Servers, ServersR}} = State) ->
    {noreply, State#state{
                servers = {lists:keydelete(Server, 1, Servers),
                           lists:keydelete(Server, 1, ServersR)}}};

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
terminate(_Reason, _State) ->
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
