-module(mdns_client_lib_worker).
-behaviour(gen_server).
-export([start_link/4]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2,
         code_change/3]).

-record(state, {name, socket, master, ip, port, timeout=1500}).


reconnect(Pid) ->
    gen_server:cast(Pid, reconnect).

start_link(Name, IP, Port, Master) ->
    gen_server:start_link(?MODULE, [Name, IP, Port, Master], []).

init([Name, IP, Port, Master]) ->
    lager:debug("[MDNS Client:~p] Initialization started.",
                [Name]),
    process_flag(trap_exit, true),
    Timeout = case application:get_env(recv_timeout) of
                  {ok, T} ->
                      T;
                  _ ->
                      1500
              end,
    case gen_tcp:connect(IP, Port,
                         [binary, {active,false}, {packet,4}],
                         Timeout) of
        {ok, Socket} ->
            lager:debug("[MDNS Client:~p] Initialization successful.",
                        [Name]),

            {ok, #state{name=Name, socket=Socket, master=Master, ip=IP,
                        port=Port, timeout=Timeout}};
        E ->
            Pid = self(),
            lager:error("[MDNS Client:~p] Initialization failed: ~p.",
                        [Name, E]),
            reconnect(Pid),
            {ok, #state{name=Name, master=Master, ip=IP, port=Port,
                        timeout=Timeout}}
    end.

handle_call({call, Command}, _From,
            #state{socket=Socket, master=Master, ip=IP, port=Port,
                   timeout=Timeout}=State) ->
    case gen_tcp:send(Socket, term_to_binary(Command)) of
        ok ->
            case gen_tcp:recv(Socket, 0, Timeout) of
                {error, E} ->
                    lager:error("[MDNS Client:~p] recv error on ~p:~p: ~p",
                                [Master, IP, Port, E]),
                    reconnect(self()),
                    {reply, {error, E}, State};
                Res ->
                    {reply, Res, State}
            end;
        E ->
            lager:error("[MDNS Client:~p] send error on ~p:~p: ~p",
                        [Master, IP, Port, E]),
            reconnect(self()),
            {reply, E, State}
    end;

handle_call(_Request, _From, State) ->
    {reply, ok, State}.

handle_cast(reconnect, State = #state{socket = S0, name = Name, master=Master,
                                      ip = IP, port = Port}) ->
    mdns_client_lib_server:downvote_endpoint(Master, Name),
    gen_tcp:close(S0),
    case gen_tcp:connect(IP, Port, [binary, {active,false}, {packet,4}], 250) of
        {ok, Socket} ->
            {noreply, State#state{socket = Socket}};
        E ->
            lager:error("[MDNS Client:~p] reconnect failed: ~p.",
                        [Name, E]),
            mdns_client_lib_server:downvote_endpoint(Master, Name, 3),
            reconnect(self()),
            {noreply, State}
    end;

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(_Info, State) ->
    {noreply, State}.

terminate(Reason, #state{name = Name, socket=Socket}) ->
    gen_tcp:close(Socket),
    lager:error("[MDNS Client:~p] Terminted with rewaon: ~p.",
                [Name, Reason]),
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.
