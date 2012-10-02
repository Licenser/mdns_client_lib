-module(zmq_mdns_connection_event).

-export([add_handler/1,
	 add_handler/2,
	 notify_connect/1,
	 notify_disconnect/1]).

add_handler(Handler) ->
    add_handler(Handler, []).

add_handler(Handler, Args) ->
    gen_event:add_handler(?MODULE, Handler, Args).

notify_connect(Service) ->
    gen_event:notify(?MODULE, {connected, Service}).

notify_disconnect(Service) ->
    gen_event:notify(?MODULE, {disconnected, Service}).
