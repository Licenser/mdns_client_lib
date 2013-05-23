-module(mdns_client_lib_worker).
-behaviour(gen_server).
-export([start_link/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2,
         code_change/3]).

-record(state, {name, socket, master}).

start_link(Args) ->
    gen_server:start_link(?MODULE, Args, []).

init([Name, IP, Port, Master]) ->
    {ok, Socket} = gen_tcp:connect(IP, Port, [binary, {active,false}, {packet,4}], 250),
    {ok, #state{name = Name, socket=Socket, master=Master}}.

handle_call({call, Command}, _From, #state{name = Name, socket=Socket, master=Master}=State) ->
    R = case gen_tcp:send(Socket, term_to_binary(Command)) of
            ok ->
                gen_tcp:recv(Socket, 0);
            E ->
                mdns_client_lib_server:downvote_endpoint(Master, Name),
                {error, E}
        end,
    {reply, R, State};

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
