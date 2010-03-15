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

-module(gen_server_udp).
-author("daiki41@gmail.com").

-behaviour(gen_server).

%% API
-export([start/3,
        start/4,
        start_link/3,
        start_link/4,
        call/2,
        call/3]).

%% gen_server callbacks
-export([init/1,
        handle_call/3,
        handle_cast/2,
        handle_info/2,
        terminate/2,
        code_change/3]).

-record(options, {
        udp_debug :: tuple(),
        udp_port :: integer(),
        udp_timeout :: integer(),
        gen_server_options :: list()
    }).

-record(state, {
        options :: tuple(),
        callbacks_module :: atom(),
        callbacks_state :: term(),
        socket :: gen_udp:socket()
    }).

-define(DEFAULT_UDP_PORT, 50210).
-define(DEFAULT_UDP_DEBUG_OPTIONS, {}).
-define(DEFAULT_UDP_TIMEOUT, 1000).
-define(UDP_SOCKET_OPTIONS, [binary]).



%%====================================================================
%% API
%%====================================================================

%% @spec start(atom(), list(), list()) -> {ok, pid()}.
start(Module, Args, RawOptions) ->
    start({local, Module}, Module, Args, RawOptions).

%% @spec start({local | global, atom()}, atom(), list(), list()) -> {ok, pid()}.
start(Name, Module, Args, RawOptions) ->
    start_common(fun gen_server:start/4, "start/4", Name, Module, Args, RawOptions).


%% @spec start_link(atom(), list(), list()) -> {ok, pid()}.
start_link(Module, Args, RawOptions) ->
    start_link({local, Module}, Module, Args, RawOptions).

%% @spec start_link({local | global, atom()}, atom(), list(), list()) -> {ok, pid()}.
start_link(Name, Module, Args, RawOptions) ->
    start_common(fun gen_server:start_link/4, "start_link/4", Name, Module, Args, RawOptions).


%% @type start_function() :: fun gen_server:start/4 | fun gen_server:start_link/4.
%% @spec start_common(start_function(), string(), atom(), list(), list()) -> {ok, pid()} | {ok, term()}.
start_common(Start, FName, Name, Module, Args, RawOptions) ->
    case analysis_options(RawOptions) of
        {ok, Options} ->
            Start(Name, ?MODULE, [Module, Options, Args], Options#options.gen_server_options),
            {ok, {node(), gen_server_udp_receive:port()}};
        {error, Message} ->
            io:format("[gen_server_udp:~p] ~p~n", [FName, Message]),
            {error, Message}
    end.

analysis_options(Options) when not is_list(Options) ->
    {error, "Options should be list()."};
analysis_options(Options) ->
    NewOptions = #options{
        udp_debug          = ?DEFAULT_UDP_DEBUG_OPTIONS,
        udp_port           = ?DEFAULT_UDP_PORT,
        udp_timeout        = ?DEFAULT_UDP_TIMEOUT,
        gen_server_options = []
    },
    analysis_options(Options, NewOptions).

analysis_options([], NewOptions) ->
    {ok, NewOptions};
analysis_options([Option | Tail], NewOptions) ->
    NewOptions = case Option of
        {udp_debug, DebugOptions} ->
            NewOptions#options{udp_debug=DebugOptions};
        {udp_port, Port} ->
            NewOptions#options{udp_port=Port};
        {udp_timeout, Timeout} ->
            NewOptions#options{udp_timeout=Timeout};
        _ ->
            NewOptions#options{gen_server_options=[Option | NewOptions#options.gen_server_options]}
    end,
    analysis_options(Tail, NewOptions).


%% @spec call(pid(), term()) -> term()
call(Pid, Message) when is_pid(Pid) ->
    gen_server:call(Pid, Message);

%% @spec call(node(), integer(), term()) -> term()
call({Node, Port}, Message) when (is_atom(Node) orelse is_tuple(Node) orelse is_list(Node)) andalso is_integer(Port) ->
    call({Node, Port}, Message, ?DEFAULT_UDP_TIMEOUT).


%% @spec call(pid(), term(), integer()) -> term()
call(Pid, Message, Timeout) when is_pid(Pid) ->
    gen_server:call(Pid, Message, Timeout);

%% @spec call(node(), integer(), term(), integer(), integer()) -> term()
call({Node, Port}, Message, Timeout) when (is_atom(Node) orelse is_tuple(Node) orelse is_list(Node))
                                                  andalso is_integer(Port)
                                                  andalso is_integer(Timeout) ->
    Ref = make_ref(),
    case gen_server_udp_receive:call({set_pid, {self(), Ref}}) of
        {ok, {Socket, ReceivePort}} ->
            From   = {{node(), ReceivePort}, Ref},
            Packet = term_to_binary({'$gen_call', From, Message}),
            gen_udp:send(Socket, Node, Port, Packet),
            io:format("sended: ~p, ~p, ~p~n", [Node, Port, Packet]),
            return(Ref, Timeout);
        {error, Reason} ->
            {error, Reason}
    end.

return(Ref, Timeout) ->
    receive
        {Ref, Result} -> Result;
        Any ->
            io:format("received: ~p~n", [Any])
    after
        Timeout -> {error, timeout}
    end.



%%====================================================================
%% gen_server callbacks
%%====================================================================

%%--------------------------------------------------------------------
%% Function: init(Args) -> {ok, State} |
%%                         {ok, State, Timeout} |
%%                         ignore               |
%%                         {stop, Reason}
%% Description: Initiates the server
%%--------------------------------------------------------------------
init([Module, Options, Args]) ->
    Port = Options#options.udp_port,
    case gen_udp:open(Port, ?UDP_SOCKET_OPTIONS) of
        {ok, Socket} ->
            case gen_server_udp_receive:start(Port + 1) of
                {ok, _Server} ->
                    call_module_init(Module, Args, Socket, Options);
                Any ->
                    {stop, Any}
            end;
        {error, Reason} ->
            {stop, {error, Reason}}
    end.

call_module_init(Module, Args, Socket, Options) ->
    case Module:init(Args) of
        {ok, CallbacksState} ->
            NewState = new_state(Options, Module, CallbacksState, Socket),
            {ok, NewState};
        {ok, CallbacksState, hibernate} ->
            NewState = new_state(Options, Module, CallbacksState, Socket),
            {ok, NewState, hibernate};
        {ok, CallbacksState, Timeout} when is_integer(Timeout) ->
            NewState = new_state(Options, Module, CallbacksState, Socket),
            {ok, NewState, Timeout};
        {stop, Reason} ->
            {stop, Reason};
        _ ->
            ignore
    end.

new_state(Options, Module, CallbacksState, Socket) ->
    #state{
        options          = Options,
        callbacks_module = Module,
        callbacks_state  = CallbacksState,
        socket           = Socket
    }.


%--------------------------------------------------------------------
%% Function: %% handle_call(Request, From, State) -> {reply, Reply, State} |
%%                                      {reply, Reply, State, Timeout} |
%%                                      {noreply, State} |
%%                                      {noreply, State, Timeout} |
%%                                      {stop, Reason, Reply, State} |
%%                                      {stop, Reason, State}
%% Description: Handling call messages
%%--------------------------------------------------------------------
handle_call(_, _From, State) ->
    {noreply, State}.


%%--------------------------------------------------------------------
%% Function: handle_cast(Msg, State) -> {noreply, State} |
%%                                      {noreply, State, Timeout} |
%%                                      {stop, Reason, State}
%% Description: Handling cast messages
%%--------------------------------------------------------------------
handle_cast(_, State) ->
    {noreply, State}.


%%--------------------------------------------------------------------
%% Function: handle_info(Info, State) -> {noreply, State} |
%%                                       {noreply, State, Timeout} |
%%                                       {stop, Reason, State}
%% Description: Handling all non call/cast messages
%%--------------------------------------------------------------------
handle_info({udp, _, _, _, Packet}, State) ->
    Module         = State#state.callbacks_module,
    CallbacksState = State#state.callbacks_state,
    case binary_to_term(Packet) of
        {'$gen_cast', Message} ->
            Return = Module:handle_cast(Message, CallbacksState),
            gen_cast_tunnel(Module, State, Return);
        {'$gen_call', From, Message} ->
            Return = Module:handle_call(Message, From, CallbacksState),
            gen_call_tunnel(From, State, Return)
    end.

gen_cast_tunnel(_, _, _) ->
    hoge.

gen_call_tunnel(From, State, {reply, Reply, NewCallbacksState}) ->
    reply(From, Reply),
    NewState = State#state{
        callbacks_state = NewCallbacksState
    },
    {noreply, NewState};
gen_call_tunnel(From, State, {reply, Reply, NewCallbacksState, hibernate}) ->
    reply(From, Reply),
    NewState = State#state{
        callbacks_state = NewCallbacksState
    },
    {noreply, NewState, hibernate};
gen_call_tunnel(From, State, {reply, Reply, NewCallbacksState, Timeout}) when is_integer(Timeout) ->
    reply(From, Reply),
    NewState = State#state{
        callbacks_state = NewCallbacksState
    },
    {noreply, NewState, Timeout};
gen_call_tunnel(_From, State, {noreply, NewCallbacksState}) ->
    NewState = State#state{
        callbacks_state = NewCallbacksState
    },
    {noreply, NewState};
gen_call_tunnel(_From, State, {noreply, NewCallbacksState, hibernate}) ->
    NewState = State#state{
        callbacks_state = NewCallbacksState
    },
    {noreply, NewState, hibernate};
gen_call_tunnel(_From, State, {noreply, NewCallbacksState, Timeout}) when is_integer(Timeout) ->
    NewState = State#state{
        callbacks_state = NewCallbacksState
    },
    {noreply, State#state{callbacks_state=NewState}, Timeout};
gen_call_tunnel(From, State, {stop, Reason, Reply, NewCallbacksState}) ->
    reply(From, Reply),
    NewState = State#state{
        callbacks_state = NewCallbacksState
    },
    {stop, Reason, State#state{callbacks_state=NewState}};
gen_call_tunnel(_From, State, {stop, Reason, NewCallbacksState}) ->
    NewState = State#state{
        callbacks_state = NewCallbacksState
    },
    {stop, Reason, State#state{callbacks_state=NewState}}.

reply(From, Message) when is_pid(From) ->
    From ! Message;
reply({From, Ref}, Message) when is_pid(From) andalso is_reference(Ref) ->
    gen_server:reply({From, Ref}, Message);
reply({{Node, Port}, Ref}, Message) when is_reference(Ref) ->
    case gen_server_udp_receive:call(get_socket) of
        {ok, Socket} ->
            Packet = term_to_binary(Message),
            gen_udp:send(Socket, Node, Port, Packet);
        Any ->
            Any
    end.


%%--------------------------------------------------------------------
%% Function: terminate(Reason, State) -> void()
%% Description: This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any necessary
%% cleaning up. When it returns, the gen_server terminates with Reason.
%% The return value is ignored.
%%--------------------------------------------------------------------
terminate(Reason, State) ->
    gen_udp:close(State#state.socket),
    Module         = State#state.callbacks_module,
    CallbacksState = State#state.callbacks_state,
    case Module:terminate(Reason, CallbacksState) of
        {ok, NewState} ->
            terminate_1({local, Module}, Module, NewState, State);
        {ok, NewState, Name} ->
            terminate_1(Name, Module, NewState, State);
        Any ->
            Any
    end.

terminate_1(Name, Module, Args, State) ->
    spawn(fun() ->
                unregister(?MODULE),
                Options = state_to_options(State),
                start_link(Name, Module, Args, Options)
        end).

state_to_options(State) when is_tuple(State) ->
    NewState = lists:nthtail(1, tuple_to_list(State)),
    state_to_options(NewState, [], []).

state_to_options([], UdpOptions, GenServerOptions) ->
    {ok, UdpOptions, GenServerOptions};
state_to_options([Type, Option | Tail], UdpOptions, GenServerOptions) ->
    if
        Type == udp_debug orelse Type == udp_port orelse Type == udp_timeout ->
            state_to_options(Tail, [{Type, Option} | UdpOptions], GenServerOptions);
        true ->
            state_to_options(Tail, UdpOptions, [{Type, Option} | GenServerOptions])
    end.


%%--------------------------------------------------------------------
%% Funcion: code_change(OldVsn, State, Extra) -> {ok, NewState}
%% Description: Convert process state when code is changed
%%--------------------------------------------------------------------
code_change(_, _, State) ->
    {ok, State}.

