%%--------------------------------------------------------------------
%% Copyright (c) 2023-2025 EMQ Technologies Co., Ltd. All Rights Reserved.
%%--------------------------------------------------------------------

-module(emqx_authz_ldap).
-behaviour(emqx_authz_source).

%% AuthZ Callbacks
-export([
    create/1,
    update/1,
    destroy/1,
    authorize/4
]).

-include_lib("emqx/include/emqx_placeholder.hrl").
-include_lib("emqx/include/logger.hrl").
-include_lib("eldap/include/eldap.hrl").
-include("emqx_auth_ldap.hrl").

-ifdef(TEST).
-compile(export_all).
-compile(nowarn_export_all).
-endif.

-define(ALLOWED_VARS, [
    ?VAR_USERNAME,
    ?VAR_CLIENTID,
    ?VAR_PEERHOST,
    ?VAR_CERT_CN_NAME,
    ?VAR_CERT_SUBJECT,
    ?VAR_ZONE,
    ?VAR_NS_CLIENT_ATTRS,
    ?VAR_LISTENER
]).

%%------------------------------------------------------------------------------
%% AuthZ Callbacks
%%------------------------------------------------------------------------------

create(Source0) ->
    ResourceId = emqx_authz_utils:make_resource_id(?AUTHZ_TYPE),
    Source = filter_placeholders(Source0),
    {ok, _Data} = emqx_authz_utils:create_resource(ResourceId, emqx_ldap, Source, ?AUTHZ_TYPE),
    Annotations = new_annotations(#{id => ResourceId}, Source),
    Source#{annotations => Annotations}.

update(Source) ->
    case emqx_authz_utils:update_resource(emqx_ldap, Source, ?AUTHZ_TYPE) of
        {error, Reason} ->
            error({load_config_error, Reason});
        {ok, Id} ->
            Annotations = new_annotations(#{id => Id}, Source),
            Source#{annotations => Annotations}
    end.

destroy(#{annotations := #{id := Id}}) ->
    emqx_authz_utils:remove_resource(Id).

authorize(
    Client,
    Action,
    Topic,
    #{
        query_timeout := QueryTimeout,
        annotations := #{id := ResourceId, cache_key_template := CacheKeyTemplate} = Annotations
    }
) ->
    Attrs = select_attrs(Action, Annotations),
    CacheKey = emqx_auth_template:cache_key(Client, CacheKeyTemplate, Attrs),
    Result = emqx_authz_utils:cached_simple_sync_query(
        CacheKey, ResourceId, {query, Client, Attrs, QueryTimeout}
    ),
    case Result of
        {ok, []} ->
            nomatch;
        {ok, [Entry]} ->
            do_authorize(Action, Topic, Attrs, Entry);
        {error, Reason} ->
            ?SLOG(error, #{
                msg => "ldap_query_failed",
                reason => emqx_utils:redact(Reason),
                resource_id => ResourceId
            }),
            nomatch
    end.

do_authorize(Action, Topic, [Attr | T], Entry) ->
    Topics = proplists:get_value(Attr, Entry#eldap_entry.attributes, []),
    case match_topic(Topic, Topics) of
        true ->
            {matched, allow};
        false ->
            do_authorize(Action, Topic, T, Entry)
    end;
do_authorize(_Action, _Topic, [], _Entry) ->
    nomatch.

new_annotations(Init, #{base_dn := BaseDN, filter := Filter} = Source) ->
    BaseDNVars = emqx_auth_template:placeholder_vars_from_str(BaseDN),
    FilterVars = emqx_auth_template:placeholder_vars_from_str(Filter),
    CacheKeyTemplate = emqx_auth_template:cache_key_template(BaseDNVars ++ FilterVars),
    State = maps:with(
        [query_timeout, publish_attribute, subscribe_attribute, all_attribute], Source
    ),
    maps:merge(Init, State#{cache_key_template => CacheKeyTemplate}).

select_attrs(#{action_type := publish}, #{publish_attribute := Pub, all_attribute := All}) ->
    [Pub, All];
select_attrs(_, #{subscribe_attribute := Sub, all_attribute := All}) ->
    [Sub, All].

match_topic(Target, Topics) ->
    lists:any(
        fun(Topic) ->
            emqx_topic:match(Target, erlang:list_to_binary(Topic))
        end,
        Topics
    ).

filter_placeholders(#{base_dn := BaseDN0, filter := Filter0} = Config) ->
    BaseDN = emqx_auth_template:escape_disallowed_placeholders_str(BaseDN0, ?ALLOWED_VARS),
    Filter = emqx_auth_template:escape_disallowed_placeholders_str(Filter0, ?ALLOWED_VARS),
    Config#{base_dn => BaseDN, filter => Filter}.
