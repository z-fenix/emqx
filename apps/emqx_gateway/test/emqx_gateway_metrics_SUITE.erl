%%--------------------------------------------------------------------
%% Copyright (c) 2022-2025 EMQ Technologies Co., Ltd. All Rights Reserved.
%%--------------------------------------------------------------------

-module(emqx_gateway_metrics_SUITE).

-include_lib("eunit/include/eunit.hrl").

-compile(export_all).
-compile(nowarn_export_all).

-define(GWNAME, mqttsn).
-define(METRIC, 'ct.test.metrics_name').
-define(CONF_DEFAULT, <<"gateway {}">>).

%%--------------------------------------------------------------------
%% setups
%%--------------------------------------------------------------------

all() -> emqx_common_test_helpers:all(?MODULE).

init_per_suite(Conf) ->
    emqx_config:erase(gateway),
    emqx_gateway_test_utils:load_all_gateway_apps(),
    emqx_common_test_helpers:load_config(emqx_gateway_schema, ?CONF_DEFAULT),
    emqx_common_test_helpers:start_apps([]),
    Conf.

end_per_suite(_Conf) ->
    emqx_common_test_helpers:stop_apps([]).

init_per_testcase(_TestCase, Conf) ->
    {ok, Pid} = emqx_gateway_metrics:start_link(?GWNAME),
    [{metrics, Pid} | Conf].

end_per_testcase(_TestCase, Conf) ->
    Pid = proplists:get_value(metrics, Conf),
    gen_server:stop(Pid),
    Conf.

%%--------------------------------------------------------------------
%% cases
%%--------------------------------------------------------------------

t_inc_dec(_) ->
    ok = emqx_gateway_metrics:inc(?GWNAME, ?METRIC),
    ok = emqx_gateway_metrics:inc(?GWNAME, ?METRIC),

    ?assertEqual(
        [{?METRIC, 2}],
        emqx_gateway_metrics:lookup(?GWNAME)
    ),

    ok = emqx_gateway_metrics:dec(?GWNAME, ?METRIC),
    ok = emqx_gateway_metrics:dec(?GWNAME, ?METRIC),

    ?assertEqual(
        [{?METRIC, 0}],
        emqx_gateway_metrics:lookup(?GWNAME)
    ).

t_handle_unexpected_msg(Conf) ->
    Pid = proplists:get_value(metrics, Conf),
    _ = Pid ! unexpected_info,
    ok = gen_server:cast(Pid, unexpected_cast),
    ok = gen_server:call(Pid, unexpected_call),
    ok.
