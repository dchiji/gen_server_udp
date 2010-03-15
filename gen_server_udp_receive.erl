%%    Copyright 2009~2010  CHIJIWA Daiki <daiki41@gmail.com>
%%    
%%    Redistribution and use in source and binary forms, with or without
%%    modification, are permitted provided that the following conditions
%%    are met:
%%    
%%         1. Redistributions of source code must retain the above copyright
%%            notice, this list of conditions and the following disclaimer.
%%    
%%         2. Redistributions in binary form must reproduce the above copyright
%%            notice, this list of conditions and the following disclaimer in
%%            the documentation and/or other materials provided with the
%%            distribution.
%%    
%%    THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
%%    "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
%%    LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS
%%    FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE FREEBSD
%%    PROJECT OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
%%    SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED
%%    TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR 
%%    PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF 
%%    LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING 
%%    NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS 
%%    SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

-module(gen_server_udp_receive).
-author("daiki41@gmail.com").

-behaviour(gen_server).

%% API
-export([start/0,
        start/1,
        start/2,
        start_debug/0,
        start_debug/1,
        start_debug/2,
        call/1,
        call/2,
        port/0]).

%% gen_server callbacks
-export([init/1,
        handle_call/3,
        handle_cast/2,
        handle_info/2,
        terminate/2,
        code_change/3]).

-record(state, {
        socket :: gen_udp:socket(),
        port :: integer(),
        timeout:: integer(),
        debug :: sys:dbg_opt()
    }).

-define(DEFAULT_TIMEOUT, 1000).
-define(DEFAULT_DEBUG_OPT, trace).
-define(DEFAULT_UDP_PORT, 50211).
-define(UDP_SOCKET_OPTIONS, [binary]).
-define(ERROR_CASE_SLEEP_TIME, 500).


%%====================================================================
%% API
%%====================================================================

%% @type timeout() :: infinity | integer().


%% @spec start() -> {ok, pid()}.
start() ->
    start(?DEFAULT_UDP_PORT, ?DEFAULT_TIMEOUT).

%% @spec start(integer()) -> {ok, pid()}.
start(Port) ->
    start(Port, ?DEFAULT_TIMEOUT).

%% @spec start(integer(), timeout()) -> {ok, pid()}.
start(Port, Timeout) ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [Port, Timeout, {}], [{timeout, Timeout}]).


%% @spec start_debug() -> {ok, pid()}.
start_debug() ->
    start(?DEFAULT_UDP_PORT, ?DEFAULT_TIMEOUT).

%% @spec start_debug(integer()) -> {ok, pid()}.
start_debug(Port) ->
    start_debug(Port, ?DEFAULT_TIMEOUT).

%% @spec start_debug(integer(), timeout()) -> {ok, pid()}.
start_debug(Port, Timeout) ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [Port, Timeout, ?DEFAULT_DEBUG_OPT], [{timeout, Timeout}, {debug, ?DEFAULT_DEBUG_OPT}]).


%% @spec call(term()) -> term().
call(Message) ->
    ?MODULE:call(Message, ?DEFAULT_TIMEOUT).

%% @spec call(term(), integer()) -> term().
call(Message, Timeout) ->
    case whereis(?MODULE) of
        undefined ->
            start(),
            call1(Message, Timeout);
        _ ->
            call1(Message, Timeout)
    end.

call1(Message, Timeout) ->
    case catch gen_server:call(?MODULE, Message, Timeout) of
        {'EXIT', {noproc, _}} ->
            timer:sleep(?ERROR_CASE_SLEEP_TIME),
            call1(Message, Timeout);
        Result ->
            Result
    end.


port() ->
    start(),
    port1().

port1() ->
    case catch gen_server:call(?MODULE, port) of
        {'EXIT', {noproc, _}} ->
            timer:sleep(?ERROR_CASE_SLEEP_TIME),
            port1();
        Result ->
            Result
    end.


%%====================================================================
%% gen_server callbacks
%%====================================================================

init([Port, Timeout, Debug]) ->
    spawn(fun() ->
                ets:new(ref_table, [set, public, named_table]),
                timer:sleep(infinity)
        end),
    case gen_udp:open(Port, ?UDP_SOCKET_OPTIONS) of
        {ok, Socket} ->
            State = #state{
                socket  = Socket,
                port    = Port,
                timeout = Timeout,
                debug   = Debug
            },
            io:format("Port=~p~n", [Port]),
            {ok, State};
        {error, Reason} ->
            {stop, {error, Reason}}
    end.


handle_call({set_pid, {Pid, Ref}}, _From, State) ->
    ets:insert(ref_table, {Ref, Pid}),
    {reply, {ok, {State#state.socket, State#state.port}}, State};


handle_call(port, _From, State) ->
    {reply, State#state.port, State};


handle_call(_, _From, State) ->
    {noreply, State}.


handle_cast(_, State) ->
    {noreply, State}.


handle_info({udp, _, _, _, Packet}, State) ->
    io:format("~n~nok~n~n"),
    case binary_to_term(Packet) of
        {StringPid, {Ref, Reply}} ->
            list_to_pid(StringPid) ! {Ref, Reply};
        {Ref, Reply} ->
            [{Ref, Pid}] = ets:lookup(ref_table, Ref),
            Pid ! {Ref, Reply},
            ets:delete(Ref);
        _ ->
            pass
    end,
    {noreply, State}.


terminate(_Reason, State) ->
    gen_udp:close(State#state.socket),
    spawn(fun() ->
                unregister(?MODULE),
                start(State#state.port, State#state.timeout)
        end),
    ok.


code_change(_, _, State) ->
    {ok, State}.

