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
-export([start_link/0,
	 send/2,
	 add_endpoint/3,
	 remove_endpoint/3,
	 register_on_connect/2,
	 register_on_disconnect/2,
	 servers/1]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
	 terminate/2, code_change/3]).

-define(SERVER, ?MODULE). 

-record(state, {
	  active = [],
	  servers = [],
	  connect_fns = [],
	  disconnect_fns = [],
	  ctx
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

register_on_connect(Pid, Fn) ->
    gen_server:cast(Pid, {on_connect, Fn}).

register_on_disconnect(Pid, Fn) ->
    gen_server:cast(Pid, {on_disconnect, Fn}).


%%--------------------------------------------------------------------
%% @doc
%% Starts the server
%%
%% @spec start_link() -> {ok, Pid} | ignore | {error, Error}
%% @end
%%--------------------------------------------------------------------
start_link() ->
    gen_server:start_link(?MODULE, [], []).

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
init([]) ->
    {ok, Ctx} = erlzmq:context(),
    {ok, #state{ctx = Ctx}}.

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

handle_call(servers, _From, #state{
		       active = Active,
		       servers = Servers} = State) ->
    {reply, {[D || {D, _} <- Active],
	     [D || {D} <- Servers]}, State};

handle_call({send, Message}, _From, #state{ctx = Ctx, 
					   active = Active,
					   servers = Servers} = State) ->
    {Res, Active1, Servers1} = send_msg(Ctx, Message, Active, Servers),
    {reply, Res, State#state{active = Active1,
			     servers = Servers1}};

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

handle_cast({on_connect, Fn},
	    #state{connect_fns = Fns} = State) ->
    {noreply, State#state{connect_fns = [Fn | Fns]}};

handle_cast({on_disconnect, Fn},
	    #state{disconnect_fns = Fns} = State) ->
    {noreply, State#state{disconnect_fns = [Fn | Fns]}};

handle_cast({add, Server, Options}, 
	    #state{active = Active,
		   servers = Servers,
		   connect_fns = Fns,
		   ctx = Ctx} = State) ->
    case lists:keyfind({Server, Options}, 1, Active ++ Servers) of
	false ->
	    case length(Active) of
		A when A < 3 ->
		    {ip, IP} = lists:keyfind(ip, 1, Options),
		    {port, Port} = lists:keyfind(port, 1, Options),
		    Socket = create_zmq(Ctx, binary_to_list(IP), binary_to_list(Port)),
		    if 
			A == 0 ->
			    [ F() || F <- Fns];
			true ->
			    ok
		    end,
		    {noreply, State#state{active=[{{Server, Options}, Socket} | Active]}};
		_ ->
		    {noreply, State#state{servers=[{{Server, Options}} | Servers]}}
	    end;
	_ ->
	    {noreply, State}
    end;


handle_cast({remove, Server, Options}, 
	    #state{servers = Servers,
		   active = Active,
		   disconnect_fns = Fns,
		   ctx = Ctx
		  } = State) ->
    case lists:keyfind({Server, Options}, 1, Active) of
	false ->
	    case {Active, lists:keydelete({Server, Options}, 1, Servers)} of
		{[], []}->
		    [F() || F <- Fns],
		    {noreply, State#state{servers=[]}};
		{_, Servers1} ->
		    {noreply, State#state{servers=Servers1}}
	    end;
	{{Server, Options}, Socket} ->
	    erlzmq:close(Socket),
	    case {lists:keydelete({Server, Options}, 1, Active), Servers} of
		{[], []}->
		    [F() || F <- Fns],
		    {noreply, State#state{servers=[],
					  active=[]}};
		{Active1, [{{S, Options1}} | Servers1]} ->
		    {ip, IP} = lists:keyfind(ip, 1, Options),
		    {port, Port} = lists:keyfind(port, 1, Options),
		    Socket = create_zmq(Ctx, binary_to_list(IP), binary_to_list(Port)),
		    Active1 = [{{S, Options1}, Socket} | Active1],
		    {noreply, State#state{servers=Servers1,
					  active=Active1}}
	    end
    end;

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
terminate(_Reason, #state{
	    active = Active,
	    ctx = Ctx
	   } = _State) ->
    [erlzmq:close(Socket) || {_, _, Socket} <- Active],
    erlzmq:term(Ctx),
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


create_zmq(Ctx, IP, Port) ->
    Endpoint = "tcp://" ++ IP ++ ":" ++ Port,
    {ok, Socket} = erlzmq:socket(Ctx, [req, {active, false}]),
    erlzmq:setsockopt(Socket, linger, 0),
    ok = erlzmq:connect(Socket, Endpoint),
    Socket.

send_msg(_, _, [], []) ->
    {{error, no_servers}, [], []};

send_msg(Ctx, Msg, [{_, Socket} = S | Active], Servers) ->
    case erlzmq:send(Socket, term_to_binary(ping), [{timeout, 50}]) of
	ok ->
	    case erlzmq:recv(Socket, [{timeout, 50}]) of			
		{ok, <<"pong">>} ->
		    case erlzmq:send(Socket, term_to_binary(Msg), [{timeout, 100}]) of
			ok ->
			    case erlzmq:recv(Socket) of
				{ok, Res} ->
				    case binary_to_term(Res) of
					noreply ->
					    {noreply, Active ++ [S], Servers};
					{reply, Reply} ->
					    {{ok, Reply}, Active ++ [S], Servers}
				    end;
				_E ->
				    erlzmq:close(Socket),
				    {Servers1, Active1} = next_server(Ctx, Active, Servers),
				    send_msg(Ctx, Msg, Active1, Servers1)
			    end;
			_E ->
			    erlzmq:close(Socket),
			    {Servers1, Active1} = next_server(Ctx, Active, Servers),
			    send_msg(Ctx, Msg, Active1, Servers1)
		    end;
		_E ->
		    erlzmq:close(Socket),
		    {Servers1, Active1} = next_server(Ctx, Active, Servers),
		    send_msg(Ctx, Msg, Active1, Servers1)
	    end
    end.

next_server(_Ctx, Active, []) ->
    {[], Active};		  

next_server(Ctx, Active, [{{S, Options}} | Servers]) ->
    {ip, IP} = lists:keyfind(ip, 1, Options),
    {port, Port} = lists:keyfind(port, 1, Options),
    Socket1 = create_zmq(Ctx, binary_to_list(IP), binary_to_list(Port)),
    {Servers, Active  ++ [{{S, Options}, Socket1}]}.
