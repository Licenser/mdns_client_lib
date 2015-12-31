-module(mdns_client_lib_worker).
-behaviour(gen_server).
-export([start_link/4]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2,
         code_change/3]).

-record(state, {name, socket, master, ip, port}).
-define(OPTS, [binary, {active, false}, {packet, 4}]).

reconnect(Pid) ->
    gen_server:cast(Pid, reconnect).

start_link(Name, IP, Port, Master) ->
    gen_server:start_link(?MODULE, [Name, IP, Port, Master], []).

init([Name, IP, Port, Master]) ->
    process_flag(trap_exit, true),
    %%timer:send_interval(1000, do_ping),
    lager:debug("[MDNS Client:~p] Initialization started.",
                [Name]),
    case gen_tcp:connect(IP, Port,
                         ?OPTS,
                         250) of
        {ok, Socket} ->
            lager:debug("[MDNS Client:~p] Initialization successful.",
                        [Name]),
            {ok, #state{name=Name, socket=Socket, master=Master, ip=IP,
                        port=Port}};
        E ->
            lager:error("[MDNS Client:~p] Initialization failed: ~p.",
                        [Name, E]),
            reconnect(self()),
            {ok, #state{name=Name, master=Master, ip=IP, port=Port}}
    end.

handle_call({stream, Command, StreamFn, Timeout}, _From,
            #state{socket=Socket, master=Master, ip=IP, port=Port}=State) ->
    case gen_tcp:send(Socket, cmd_bin(Command)) of
        ok ->
            read_stream(StreamFn, Timeout, State);
        E ->
            reply_and_reconnect(send, Master, IP, Port, E, State)
    end;

handle_call({call, Command, Timeout}, _From,
            #state{socket=Socket, master=Master, ip=IP, port=Port}=State) ->
    case gen_tcp:send(Socket, cmd_bin(Command)) of
        ok ->
            case gen_tcp:recv(Socket, 0, Timeout) of
                {error, E} ->
                    reply_and_reconnect(recv, Master, IP, Port, {error, E},
                                        State);
                Res ->
                    {reply, Res, State}
            end;
        E ->
            reply_and_reconnect(send, Master, IP, Port, E, State)
    end.
read_stream(StreamFn, Timeout,
            #state{socket=Socket, master=Master, ip=IP, port=Port}=State) ->
    case gen_tcp:recv(Socket, 0, Timeout) of
        {error, E} ->
            reply_and_reconnect(recv, Master, IP, Port, {error, E}, State);
        {ok, Res} ->
            case binary_to_term(Res) of
                stream_start ->
                    read_stream1(StreamFn, Timeout, State);
                E ->
                    reply_and_reconnect(recv, Master, IP, Port, E, State)
            end
    end.

read_stream1(StreamFn, Timeout,
             #state{socket=Socket, master=Master, ip=IP, port=Port}=State) ->
    case gen_tcp:recv(Socket, 0, Timeout) of
        {error, E} ->
            reply_and_reconnect(recv, Master, IP, Port, E, State);
        {ok, Res} ->
            case binary_to_term(Res) of
                stream_end ->
                    StreamFn(done),
                    {reply, ok, State};
                {stream, Data} ->
                    StreamFn({data, Data}),
                    read_stream1(StreamFn, Timeout, State);
                E ->
                    StreamFn({error, E}),
                    reply_and_reconnect(recv, Master, IP, Port, E, State)
            end
    end.



handle_cast(reconnect, State = #state{socket = S0, name = Name, master=Master,
                                      ip = IP, port = Port}) ->
    mdns_client_lib_server:downvote_endpoint(Master, Name),
    gen_tcp:close(S0),
    case gen_tcp:connect(IP, Port, ?OPTS, 250) of
        {ok, Socket} ->
            {noreply, State#state{socket = Socket}};
        E ->
            lager:error("[MDNS Client:~p] reconnect failed: ~p.",
                        [Name, E]),
            mdns_client_lib_server:downvote_endpoint(Master, Name, 3),
            reconnect(self()),
            {noreply, State}
    end.

handle_info(do_ping,
            #state{socket=Socket, master=Master, ip=IP, port=Port}=State) ->
    Pong = term_to_binary(pong),
    case gen_tcp:send(Socket, term_to_binary(ping)) of
        ok ->
            case gen_tcp:recv(Socket, 0, 500) of
                {error, E} ->
                    noreply_and_reconnect(recv, Master, IP, Port, E, State);
                {ok, Res} when Res =:= Pong  ->
                    {noreply, State}
            end;
        E ->
            noreply_and_reconnect(send, Master, IP, Port, E, State)
    end;

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, #state{socket=undefined}) ->
    ok;

terminate(Reason, #state{name = Name, socket=Socket}) ->
    gen_tcp:close(Socket),
    lager:error("[MDNS Client:~p] Terminted with reason: ~p.",
                [Name, Reason]),
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

noreply_and_reconnect(Type, Master, IP, Port, E, State) ->
    error_and_reconnect(Type, Master, IP, Port, E),
    {noreply, State}.

reply_and_reconnect(Type, Master, IP, Port, E, State) ->
    error_and_reconnect(Type, Master, IP, Port, E),
    {reply, E, State}.

error_and_reconnect(Type, Master, IP, Port, E) ->
    lager:error("[MDNS Client:~p] ~s error on ~p:~p: ~p",
                [Type, Master, IP, Port, E]),
    reconnect(self()).

cmd_bin(Command) ->
    case seq_trace:get_token() of
        [] ->
            term_to_binary(Command);
        _Tkn ->
            {serial, {Previous, Current}} = seq_trace:get_token(serial),
            %% Since we got thos over TCP we need to 'update' the serial
            %% ourselfs
            seq_trace:set_token(serial, {Previous, Current + 1}),
            Tkn = seq_trace:get_token(),
            term_to_binary({trace, Tkn, Command})
    end.
