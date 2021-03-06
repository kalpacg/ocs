%%% mod_ocs_rest_get.erl
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% @copyright 2016 SigScale Global Inc.
%%% @end
%%% Licensed under the Apache License, Version 2.0 (the "License");
%%% you may not use this file except in compliance with the License.
%%% You may obtain a copy of the License at
%%%
%%%     http://www.apache.org/licenses/LICENSE-2.0
%%%
%%% Unless required by applicable law or agreed to in writing, software
%%% distributed under the License is distributed on an "AS IS" BASIS,
%%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%%% See the License for the specific language governing permissions and
%%% limitations under the License.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%
-module(mod_ocs_rest_get).
-copyright('Copyright (c) 2016 SigScale Global Inc.').

-export([do/1]).

-include_lib("inets/include/httpd.hrl"). 

-spec do(ModData) -> Result when
	ModData :: #mod{},
	Result :: {proceed, OldData} | {proceed, NewData} | {break, NewData} | done,
	OldData :: list(),
	NewData :: [{response,{StatusCode,Body}}] | [{response,{response,Head,Body}}]
			| [{response,{already_sent,StatusCode,Size}}],
	StatusCode :: integer(),
	Body :: list() | nobody | {Fun, Arg},
	Head :: [HeaderOption],
	HeaderOption :: {Option, Value} | {code, StatusCode},
	Option :: accept_ranges | allow
	| cache_control | content_MD5
	| content_encoding | content_language
	| content_length | content_location
	| content_range | content_type | date
	| etag | expires | last_modified
	| location | pragma | retry_after
	| server | trailer | transfer_encoding,
	Value :: string(),
	Size :: term(),
	Fun :: fun((Arg) -> sent| close | Body),
	Arg :: [term()].
%% @doc Erlang web server API callback function.
do(#mod{method = Method, parsed_header = Headers, request_uri = Uri,
				data = Data} = ModData) ->
	case Method of
		"GET" ->
			case proplists:get_value(status, Data) of
				{_StatusCode, _PhraseArgs, _Reason} ->
					{proceed, Data};
				undefined ->
					case proplists:get_value(response, Data) of
						undefined ->
							{_, Resource} = lists:keyfind(resource, 1, Data),
							content_type_available(Headers, Uri, Resource, ModData);
						_Response ->
							{proceed,  Data}
					end
			end;
		_ ->
			{proceed, Data}
	end.

%% @hidden
content_type_available(Headers, Uri, Resource, ModData) ->
	case lists:keyfind("accept", 1, Headers) of
		{_, RequestingType} ->
			AvailableTypes = Resource:content_types_provided(),
			case lists:member(RequestingType, AvailableTypes) of
				true ->
					do_get(Uri, Resource, ModData);
				false ->
					Response = "<h2>HTTP Error 415 - Unsupported Media Type</h2>",
					{break, [{response, {415, Response}}]}
			end;
		_ ->
			Response = "<h2>HTTP Error 400 - Bad Request</h2>",
			{break, [{response, {400, Response}}]}
	end.

%% @hidden
do_get(Uri, Resource, ModData) ->
	case string:tokens(Uri, "/") of
		[_, "v1", _] ->
			case Resource:perform_get_all() of
				{body, Body} ->
					send_response(Body, ModData);
				{error, ErrorCode} ->
					{break, [{response, {ErrorCode, "<h1>Not Found</h1>"}}]}
			end;
		[_, "v1", _, Identity] ->
			case Resource:perform_get(Identity) of
				{body, Body} ->
					send_response(Body, ModData);
				{error, ErrorCode} ->
					{break, [{response, {ErrorCode, "<h1>Not Found</h1>"}}]}
			end;
		_ ->
			{break, [{response, {404, "<h1>NOT FOUND</h1>"}}]}
end.

%% @hidden
send_response(ResponseBody, #mod{data = Data} = ModData) ->
	Size = integer_to_list(iolist_size(ResponseBody)),
	Accept = proplists:get_value(accept, Data),
	Headers = [{content_length, Size}, {content_type, Accept}],
	send(ModData, 200, Headers, ResponseBody),
	{proceed,[{response,{already_sent,201, Size}}]}.

%% @hidden
send(#mod{socket = Socket, socket_type = SocketType} = ModData,
     StatusCode, Headers, ResponseBody) ->
    httpd_response:send_header(ModData, StatusCode, Headers),
    httpd_socket:deliver(SocketType, Socket, ResponseBody).

