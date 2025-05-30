%%--------------------------------------------------------------------
%% Copyright (c) 2024-2025 EMQ Technologies Co., Ltd. All Rights Reserved.
%%--------------------------------------------------------------------

%% @doc This module implements the config schema for emqx_mt app.
-module(emqx_mt_schema).

-include_lib("typerefl/include/types.hrl").
-include_lib("hocon/include/hoconsc.hrl").
-include("emqx_mt.hrl").

%% `hocon_schema' API
-export([
    namespace/0,
    roots/0,
    fields/1,
    desc/1
]).

namespace() -> emqx_mt.

roots() ->
    [
        {?CONF_ROOT_KEY, mk(ref("config"), #{importance => ?IMPORTANCE_MEDIUM})}
    ].

fields("config") ->
    [
        {default_max_sessions,
            mk(
                hoconsc:union(
                    [infinity, non_neg_integer()]
                ),
                #{
                    desc => ?DESC(default_max_sessions),
                    importance => ?IMPORTANCE_HIGH,
                    default => infinity
                }
            )},
        {allow_only_managed_namespaces,
            mk(
                boolean(),
                #{
                    desc => ?DESC("allow_only_managed_namespaces"),
                    importance => ?IMPORTANCE_HIGH,
                    default => false
                }
            )}
    ].

mk(Type, Meta) -> hoconsc:mk(Type, Meta).
ref(Name) -> hoconsc:ref(?MODULE, Name).

desc("config") -> ?DESC("config");
desc(_) -> undefined.
