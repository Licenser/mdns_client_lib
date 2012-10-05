%%%-------------------------------------------------------------------
%%% @author Heinz Nikolaus Gies <heinz@licenser.net>
%%% @copyright (C) 2012, Heinz Nikolaus Gies
%%% @doc
%%%
%%% @end
%%% Created : 19 Aug 2012 by Heinz Nikolaus Gies <heinz@licenser.net>
%%%-------------------------------------------------------------------
-module(zmq_mdns_client_server).

-behaviour(gen_server).

%% API
-export([start_link/1,
	 send/2,
	 add_endpoint/3,
	 remove_endpoint/3,
	 servers/1]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
	 terminate/2, code_change/3]).

-record(state, {
	  servers = {[], []},
	  service
	 }).

%%%===================================================================
%%% API
%%%===================================================================

add_endpoint(Pid, Server, Options) ->
    gen_server:cast(Pid, {add, Server, Options}).

remove_endpoint(Pid, Server, Options) ->
    gen_server:cast(Pid, {remove, Server, Options}).

servers(Pid) ->
    gen_server:call(Pid, servers).

send(Pid, Message) ->
    gen_server:call(Pid, {send, Message}).

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
	   zmq_mdns_client_mdns_handler,
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

handle_call({send, Message}, _From, #state{servers = Servers} = State) ->
    {Res, Servers1} = send_msg(Message, Servers),
    {reply, Res, State#state{servers = Servers1}};

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
    case lists:keyfind({Server, Options}, 1, Servers) of
	false ->
	    {ip, IP} = lists:keyfind(ip, 1, Options),
	    {port, Port} = lists:keyfind(port, 1, Options),
	    IPort = list_to_integer(binary_to_list(Port)),
	    IPS = binary_to_list(IP),
	    case Servers of
		[] ->
		    zmq_mdns_connection_event:notify_connect(Service);
		_ ->
		    ok
	    end,
	    {noreply, State#state{servers={[{{Server, Options}, IPS, IPort} | Servers], ServersR}}};
	_ ->
	    {noreply, State}
    end;


handle_cast({remove, _Server, _Options},
	    #state{servers = {[], []}} = State) -> 
    {noreply, State};

handle_cast({remove, Server, Options}, 
	    #state{servers = {[{{Server, Options}, _, _}], []},
		   service = Service} = State) ->
    zmq_mdns_connection_event:notify_disconnect(Service),
    {noreply, State#state{servers = {[], []}}};

handle_cast({remove, Server, Options}, 
	    #state{servers = {[], [{{Server, Options}, _, _}]},
		   service = Service} = State) ->
    zmq_mdns_connection_event:notify_disconnect(Service),
    {noreply, State#state{servers = {[], []}}};

handle_cast({remove, Server, Options}, 
	    #state{servers = {Servers, ServersR}} = State) ->
    {noreply, State#state{
		servers = {lists:keydelete({Server, Options}, 1, Servers), 
			   lists:keydelete({Server, Options}, 1, ServersR)}}};

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

send_msg(_, {[], []}) ->
    {{error, no_servers}, {[], []}};

send_msg(Msg, {[], Servers}) ->
    send_msg(Msg, {Servers, []});

send_msg(Msg, {[{_, IP, Port}=Server| Servers], ServersR}) ->
    case gen_tcp:connect(IP, Port, [binary, {active,false}]) of
	{ok, Socket} ->
	    case gen_tcp:send(Socket, term_to_binary(Msg)) of
		ok ->
		    case gen_tcp:recv(Socket, 0) of
			{ok, Res} ->
			    gen_tcp:close(Socket),
			    case binary_to_term(Res) of
				noreply ->
				    {noreply, {Servers, [Server | ServersR]}};
				{reply, Reply} ->
				    {{ok, Reply}, {Servers, [Server | ServersR]}}
			    end;
			_ ->
			    send_msg(Msg, {Servers, ServersR})
		    end;
		_ ->
		    send_msg(Msg, {Servers, ServersR})
	    end;
	_ ->
	    send_msg(Msg, {Servers, ServersR})
    end.
