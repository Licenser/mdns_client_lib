-module(mdns_client_lib_worker).
-behaviour(gen_server).
-export([start_link/4]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2,
         code_change/3]).

-record(state, {name, socket, master, ip, port}).

start_link(Name, IP, Port, Master) ->
    gen_server:start_link(?MODULE, [Name, IP, Port, Master], []).

init([Name, IP, Port, Master]) ->
    {ok, Socket} = gen_tcp:connect(IP, Port, [binary, {active,false}, {packet,4}], 250),
    {ok, #state{name = Name, socket=Socket, master=Master, ip = IP, port = Port}}.

handle_call({call, Command}, _From, #state{name = Name, socket=Socket, master=Master, ip = IP, port = Port}=State) ->
    case gen_tcp:send(Socket, term_to_binary(Command)) of
        ok ->
            case gen_tcp:recv(Socket, 0, 1500) of
                {error, E} when E =:= enotconn orelse E =:= closed ->
                    lager:error("[mdns_client_lib:~p] recv error on ~p:~p: ~p", [Master, IP, Port, E]),
                    {ok, Socket1} = gen_tcp:connect(IP, Port, [binary, {active,false}, {packet,4}], 250),
                    mdns_client_lib_server:downvote_endpoint(Master, Name),
                    {reply, {error, E}, State#state{socket = Socket1}};
                {error, _} = E ->
                    lager:error("[mdns_client_lib:~p] recv error on ~p:~p: ~p", [Master, IP, Port, E]),
                    mdns_client_lib_server:downvote_endpoint(Master, Name),
                    {reply, E, State};
                Res ->
                    {reply, Res, State}
            end;
        {error, E} when E =:= enotconn orelse E =:= closed ->
            lager:error("[mdns_client_lib:~p] send error on ~p:~p: ~p", [Master, IP, Port, E]),
            {ok, Socket1} = gen_tcp:connect(IP, Port, [binary, {active,false}, {packet,4}], 250),
            mdns_client_lib_server:downvote_endpoint(Master, Name),
            {reply, {error, E}, State#state{socket = Socket1}};
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
    ok = gen_tcp:close(Socket),
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.
