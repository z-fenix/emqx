%%--------------------------------------------------------------------
%% Copyright (c) 2020-2025 EMQ Technologies Co., Ltd. All Rights Reserved.
%%--------------------------------------------------------------------
-module(emqx_auto_subscribe_SUITE).

-compile(export_all).
-compile(nowarn_export_all).

-include_lib("eunit/include/eunit.hrl").
-include_lib("common_test/include/ct.hrl").
-import(emqx_config_SUITE, [prepare_conf_file/3]).

-define(TOPIC_C, <<"/c/${clientid}">>).
-define(TOPIC_U, <<"/u/${username}">>).
-define(TOPIC_H, <<"/h/${host}">>).
-define(TOPIC_P, <<"/p/${port}">>).
-define(TOPIC_A, <<"/client/${clientid}/username/${username}/host/${host}/port/${port}">>).
-define(TOPIC_S, <<"/topic/simple">>).

-define(TOPICS, [?TOPIC_C, ?TOPIC_U, ?TOPIC_H, ?TOPIC_P, ?TOPIC_A, ?TOPIC_S]).

-define(ENSURE_TOPICS, [
    <<"/c/auto_sub_c">>,
    <<"/u/auto_sub_u">>,
    ?TOPIC_S
]).

-define(CLIENT_ID, <<"auto_sub_c">>).
-define(CLIENT_USERNAME, <<"auto_sub_u">>).

all() ->
    emqx_common_test_helpers:all(?MODULE).

init_per_suite(Config) ->
    meck:new(emqx_schema, [non_strict, passthrough, no_history, no_link]),
    meck:expect(emqx_schema, fields, fun
        ("auto_subscribe") ->
            meck:passthrough(["auto_subscribe"]) ++
                emqx_auto_subscribe_schema:fields("auto_subscribe");
        (F) ->
            meck:passthrough([F])
    end),

    meck:new(emqx_resource, [non_strict, passthrough, no_history, no_link]),
    meck:expect(emqx_resource, create, fun(_, _, _) -> {ok, meck_data} end),
    meck:expect(emqx_resource, update, fun(_, _, _, _) -> {ok, meck_data} end),
    meck:expect(emqx_resource, remove, fun(_) -> ok end),

    ASCfg = <<
        "auto_subscribe {\n"
        "            topics = [\n"
        "                {\n"
        "                    topic = \"/c/${clientid}\"\n"
        "                },\n"
        "                {\n"
        "                    topic = \"/u/${username}\"\n"
        "                },\n"
        "                {\n"
        "                    topic = \"/h/${host}\"\n"
        "                },\n"
        "                {\n"
        "                    topic = \"/p/${port}\"\n"
        "                },\n"
        "                {\n"
        "                    topic = \"/client/${clientid}/username/${username}/host/${host}/port/${port}\"\n"
        "                },\n"
        "                {\n"
        "                    topic = \"/topic/simple\"\n"
        "                    qos   = 1\n"
        "                    rh    = 0\n"
        "                    rap   = 0\n"
        "                    nl    = 0\n"
        "                }\n"
        "            ]\n"
        "        }"
    >>,
    Apps = emqx_cth_suite:start(
        [
            emqx,
            emqx_conf,
            {emqx_auto_subscribe, ASCfg},
            emqx_management,
            emqx_mgmt_api_test_util:emqx_dashboard()
        ],
        #{work_dir => emqx_cth_suite:work_dir(Config)}
    ),
    [{apps, Apps} | Config].

init_per_testcase(t_get_basic_usage_info, Config) ->
    {ok, _} = emqx_auto_subscribe:update([]),
    Config;
init_per_testcase(t_auto_subscribe_reload_from_file, Config) ->
    {ok, _} = emqx_auto_subscribe:update([]),
    Config;
init_per_testcase(_TestCase, Config) ->
    Config.

end_per_testcase(t_get_basic_usage_info, _Config) ->
    {ok, _} = emqx_auto_subscribe:update([]),
    ok;
end_per_testcase(t_auto_subscribe_reload_from_file, _Config) ->
    {ok, _} = emqx_auto_subscribe:update([]),
    ok;
end_per_testcase(_TestCase, _Config) ->
    ok.

topic_config(T) ->
    #{
        topic => T,
        qos => 0,
        rh => 0,
        rap => 0,
        nl => 0
    }.

end_per_suite(Config) ->
    Apps = ?config(apps, Config),
    emqx_cth_suite:stop(Apps),
    ok.

t_auto_subscribe(_) ->
    emqx_auto_subscribe:update([#{<<"topic">> => Topic} || Topic <- ?TOPICS]),
    {ok, Client} = emqtt:start_link(#{username => ?CLIENT_USERNAME, clientid => ?CLIENT_ID}),
    {ok, _} = emqtt:connect(Client),
    timer:sleep(200),
    ?assertEqual(check_subs(length(?TOPICS)), ok),
    emqtt:disconnect(Client),
    ok.
t_auto_subscribe_reload_from_file(Config) ->
    ConfBin = hocon_pp:do(
        #{<<"auto_subscribe">> => #{<<"topics">> => [#{<<"topic">> => Topic} || Topic <- ?TOPICS]}},
        #{}
    ),
    ConfFile = prepare_conf_file(?FUNCTION_NAME, ConfBin, Config),
    ok = emqx_conf_cli:conf(["load", "--replace", ConfFile]),
    {ok, Client} = emqtt:start_link(#{username => ?CLIENT_USERNAME, clientid => ?CLIENT_ID}),
    {ok, _} = emqtt:connect(Client),
    timer:sleep(200),
    ?assertEqual(check_subs(length(?TOPICS)), ok),
    emqtt:disconnect(Client),
    ok.

t_update(_) ->
    Path = emqx_mgmt_api_test_util:api_path(["mqtt", "auto_subscribe"]),
    Auth = emqx_mgmt_api_test_util:auth_header_(),
    Body = [#{topic => ?TOPIC_S}],
    {ok, Response} = emqx_mgmt_api_test_util:request_api(put, Path, "", Auth, Body),
    ResponseMap = emqx_utils_json:decode(Response),
    ?assertEqual(1, erlang:length(ResponseMap)),

    BadBody1 = #{topic => ?TOPIC_S},
    ?assertMatch(
        {error, {"HTTP/1.1", 400, "Bad Request"}},
        emqx_mgmt_api_test_util:request_api(put, Path, "", Auth, BadBody1)
    ),
    BadBody2 = [#{topic => ?TOPIC_S, qos => 3}],
    ?assertMatch(
        {error, {"HTTP/1.1", 400, "Bad Request"}},
        emqx_mgmt_api_test_util:request_api(put, Path, "", Auth, BadBody2)
    ),
    BadBody3 = [#{topic => ?TOPIC_S, rh => 10}],
    ?assertMatch(
        {error, {"HTTP/1.1", 400, "Bad Request"}},
        emqx_mgmt_api_test_util:request_api(put, Path, "", Auth, BadBody3)
    ),
    BadBody4 = [#{topic => ?TOPIC_S, rap => -1}],
    ?assertMatch(
        {error, {"HTTP/1.1", 400, "Bad Request"}},
        emqx_mgmt_api_test_util:request_api(put, Path, "", Auth, BadBody4)
    ),
    BadBody5 = [#{topic => ?TOPIC_S, nl => -1}],
    ?assertMatch(
        {error, {"HTTP/1.1", 400, "Bad Request"}},
        emqx_mgmt_api_test_util:request_api(put, Path, "", Auth, BadBody5)
    ),

    {ok, Client} = emqtt:start_link(#{username => ?CLIENT_USERNAME, clientid => ?CLIENT_ID}),
    {ok, _} = emqtt:connect(Client),
    timer:sleep(100),
    ?assertEqual(check_subs(ets:tab2list(emqx_suboption), [?TOPIC_S]), ok),
    emqtt:disconnect(Client),

    {ok, GETResponse} = emqx_mgmt_api_test_util:request_api(get, Path),
    GETResponseMap = emqx_utils_json:decode(GETResponse),
    ?assertEqual(1, erlang:length(GETResponseMap)),
    ok.

t_get_basic_usage_info(_Config) ->
    ?assertEqual(#{auto_subscribe_count => 0}, emqx_auto_subscribe:get_basic_usage_info()),
    AutoSubscribeTopics =
        lists:map(
            fun(N) ->
                Num = integer_to_binary(N),
                Topic = <<"auto/", Num/binary>>,
                #{<<"topic">> => Topic}
            end,
            lists:seq(1, 3)
        ),
    {ok, _} = emqx_auto_subscribe:update(AutoSubscribeTopics),
    ?assertEqual(#{auto_subscribe_count => 3}, emqx_auto_subscribe:get_basic_usage_info()),
    ok.

check_subs(Count) ->
    Subs = ets:tab2list(emqx_suboption),
    ct:pal("--->  ~p ~p ~n", [Subs, Count]),
    ?assert(length(Subs) >= Count),
    check_subs((Subs), ?ENSURE_TOPICS).

check_subs([], []) ->
    ok;
check_subs([{{Topic, _}, #{subid := ?CLIENT_ID}} | Subs], List) ->
    check_subs(Subs, lists:delete(Topic, List));
check_subs([_ | Subs], List) ->
    check_subs(Subs, List).
