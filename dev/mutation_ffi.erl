-module(mutation_ffi).
-export([parallel_map/2, monotonic_milliseconds/0]).

%% Apply Fun to every item in its own process and return the results in order.
parallel_map(Items, Fun) ->
    Parent = self(),
    Refs = [begin
                Ref = make_ref(),
                spawn_link(fun() -> Parent ! {Ref, Fun(Item)} end),
                Ref
            end || Item <- Items],
    [receive {Ref, Result} -> Result end || Ref <- Refs].

monotonic_milliseconds() ->
    erlang:monotonic_time(millisecond).
