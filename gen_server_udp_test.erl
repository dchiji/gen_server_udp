-module(gen_server_udp_test).
-export([start/0, test/0, init/1, handle_call/3]).

start() ->
    gen_server_udp:start_link({local, ?MODULE}, ?MODULE, [], []).

test() ->
    {ok, Server} = start(),
    io:format("Server=~p~n", [Server]),
    io:format("> ~p~n", [gen_server_udp:call(Server, test)]).

init(Args) ->
    {ok, Args}.

handle_call(test, _From, State) ->
    {reply, ok, State}.
