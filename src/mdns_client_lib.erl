-module(mdns_client_lib).

-export([start/0,
	 instance/1,
	 call/2,
	 cast/2,
	 servers/1
	]).

%%--------------------------------------------------------------------
%% @doc
%% Calls the client, if no servers are present it will return en
%% error. This call is syncronous. Not being connected has to be
%% handled by the library user.
%%
%% @spec call(Pid::pid(), Msg::term()) -> {ok, Reply::term()} |
%%                         {error, no_server}
%% @end
%%--------------------------------------------------------------------


-spec call(Pid::pid(), Msg::term()) -> {ok, Reply::term()} | {error, no_server}.
call(Pid, Msg) ->
    mdns_client_lib_server:call(Pid, Msg).

%%--------------------------------------------------------------------
%% @doc
%% Sends a ansyncronous message to the server. This call is 
%% assyncronous. Since it's not possible to know if there was a 
%% successful send the library takes care of resending, order is 
%% not guaranteed.
%%
%% @spec cast(Pid::pid(), Msg::term()) -> ok
%%
%% @end
%%--------------------------------------------------------------------

-spec cast(Pid::pid(), Msg::term()) -> ok.
cast(Pid, Msg) ->
    mdns_client_lib_server:cast(Pid, Msg).

%%--------------------------------------------------------------------
%% @doc
%% Creates a new instance of a mdns client library, this should
%% be called with your service name to initialize a connection.
%% It can be called twice or more with different services to allow
%% talking to multiple endpoints.
%%
%% @spec instance(Service::string()) -> Pid::pid()
%% @end
%%--------------------------------------------------------------------

-spec instance(Service::string()) -> Pid::pid().
instance(Service) ->
    supervisor:start_child(mdns_client_lib_sup, [Service]).


%%--------------------------------------------------------------------
%% @doc
%% Lists all servers discovered by an isntance, this is mostly
%% informational.
%%
%% @spec servers(Pid::pid()) -> [Server::term()]
%% @end
%%--------------------------------------------------------------------

-spec servers(Pid::pid()) -> [Server::term()].
servers(Pid) ->
    mdns_client_lib_server:servers(Pid).

-spec start() -> any().
start() ->
    application:start(mdns_client_lib).
