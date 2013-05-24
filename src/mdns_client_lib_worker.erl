-module(mdns_client_lib_worker).
-behaviour(gen_server).
-export([start_link/4]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2,
         code_change/3]).

-record(state, {name, socket, master, ip, port, timeout=1500}).

start_link(Name, IP, Port, Master) ->
    gen_server:start_link(?MODULE, [Name, IP, Port, Master], []).

init([Name, IP, Port, Master]) ->
    process_flag(trap_exit, true),
    Timeout = case application:get_env(recv_timeout) of
                  {ok, T} ->
                      T;
                  _ ->
                      1500
              end,
    {ok, Socket} = gen_tcp:connect(IP, Port, [binary, {active,false}, {packet,4}], Timeout),
    {ok, #state{name=Name, socket=Socket, master=Master, ip=IP, port=Port, timeout=Timeout}}.

handle_call({call, Command}, _From,
            #state{name=Name, socket=Socket, master=Master, ip=IP, port=Port, timeout=Timeout}=State) ->
    case gen_tcp:send(Socket, term_to_binary(Command)) of
        ok ->
            case gen_tcp:recv(Socket, 0, Timeout) of
                {error, E} when E =:= enotconn orelse E =:= closed ->
                    lager:error("[mdns_client_lib:~p] recv error on ~p:~p: ~p", [Master, IP, Port, E]),
                    {reply, {error, E}, reconnect(State)};
                {error, _} = E ->
                    lager:error("[mdns_client_lib:~p] recv error on ~p:~p: ~p", [Master, IP, Port, E]),
                    mdns_client_lib_server:downvote_endpoint(Master, Name),
                    {reply, E, State};
                Res ->
                    {reply, Res, State}
            end;
        {error, E} when E =:= enotconn orelse E =:= closed ->
            lager:error("[mdns_client_lib:~p] send error on ~p:~p: ~p", [Master, IP, Port, E]),
            {reply, {error, E}, reconnect(State)};
        E ->
            lager:error("[mdns_client_lib:~p] send error on ~p:~p: ~p", [Master, IP, Port, E]),
            mdns_client_lib_server:downvote_endpoint(Master, Name),
            {reply, E, State}
    end;

handle_call(_Request, _From, State) ->
    {reply, ok, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, #state{socket=Socket}) ->
    gen_tcp:close(Socket),
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

reconnect(State = #state{name = Name, master=Master, ip = IP, port = Port}) ->
    mdns_client_lib_server:downvote_endpoint(Master, Name),
    case gen_tcp:connect(IP, Port, [binary, {active,false}, {packet,4}], 250) of
        {ok, Socket} ->
            gen_tcp:connect(IP, Port, [binary, {active,false}, {packet,4}], 250),
            State#state{socket = Socket};
        _ ->
            mdns_client_lib_server:downvote_endpoint(Master, Name),
            State
    end.
