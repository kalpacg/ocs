%%% ocs_simple_auth_SUITE.erl
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
%%%  @doc Test suite for authentication 
%%% 	of the {@link //ocs. ocs} application.
%%%
-module(ocs_simple_auth_SUITE).
-copyright('Copyright (c) 2016 SigScale Global Inc.').

%% common_test required callbacks
-export([suite/0, sequences/0, all/0]).
-export([init_per_suite/1, end_per_suite/1]).
-export([init_per_testcase/2, end_per_testcase/2]).

-compile(export_all).

-include_lib("radius/include/radius.hrl").
-include("ocs_eap_codec.hrl").
-include_lib("common_test/include/ct.hrl").

%%---------------------------------------------------------------------
%%  Test server callback functions
%%---------------------------------------------------------------------

-spec suite() -> DefaultData :: [tuple()].
%% Require variables and set default values for the suite.
%%
suite() ->
	[{userdata, [{doc, "Test suite for authentication in OCS"}]},
	{timetrap, {minutes, 1}},
	{require, radius_username}, {default_config, radius_username, "ocs"},
	{require, radius_password}, {default_config, radius_password, "ocs123"},
	{require, radius_shared_secret},{default_config, radius_shared_secret, "xyzzy5461"}].

-spec init_per_suite(Config :: [tuple()]) -> Config :: [tuple()].
%% Initiation before the whole suite.
%%
init_per_suite(Config) ->
	ok = ocs_test_lib:initialize_db(),
	ok = ocs_test_lib:start(),
	AuthAddress = {127, 0, 0, 1},
	{ok, DiscPort} = application:get_env(ocs, radius_disconnect_port),
	Protocol = ct:get_config(protocol),
	SharedSecret = ct:get_config(radius_shared_secret),
	ok = ocs:add_client({127, 0, 0, 1}, DiscPort, Protocol, SharedSecret),
	NasId = atom_to_list(node()),
	Config1 = [{nas_id, NasId} | Config],
	CalledStationId = "E4-8D-8C-D6-E0-AC:TestSSID",
	[{called_id, CalledStationId} | Config1].

-spec end_per_suite(Config :: [tuple()]) -> any().
%% Cleanup after the whole suite.
%%
end_per_suite(Config) ->
	ok = ocs_test_lib:stop(),
	Config.

-spec init_per_testcase(TestCase :: atom(), Config :: [tuple()]) -> Config :: [tuple()].
%% Initiation before each test case.
%%
init_per_testcase(_TestCase, Config) ->
	{ok, IP} = application:get_env(ocs, radius_auth_addr),
	{ok, Socket} = gen_udp:open(0, [{active, false}, inet, {ip, IP}, binary]),
	[{socket, Socket} | Config].

-spec end_per_testcase(TestCase :: atom(), Config :: [tuple()]) -> any().
%% Cleanup after each test case.
%%
end_per_testcase(_TestCase, Config) ->
	Socket = ?config(socket, Config),
	ok = 	gen_udp:close(Socket).

-spec sequences() -> Sequences :: [{SeqName :: atom(), Testcases :: [atom()]}].
%% Group test cases into a test sequence.
%%
sequences() -> 
	[].

-spec all() -> TestCases :: [Case :: atom()].
%% Returns a list of all test cases in this test suite.
%%
all() -> 
	[simple_authentication, out_of_credit, bad_password, unknown_username].

%%---------------------------------------------------------------------
%%  Test cases
%%---------------------------------------------------------------------

simple_authentication() ->
	[{userdata, [{doc, "Send AccessAccept to the peer"}]}].

simple_authentication(Config) ->
	Id = 1,
	NasId = ?config(nas_id, Config),
	CalledStationId = ?config(called_id, Config),
	MAC = "DD:EE:DD:EE:BB:AA",
	MACtokens = string:tokens(MAC, ":"),
	CallingStationId = string:join(MACtokens, "-"),
	PeerID = string:to_lower(lists:append(MACtokens)),
	PeerPassword = ocs:generate_password(),
	ok = ocs:add_subscriber(PeerID, PeerPassword, [], 10000),
	Authenticator = radius:authenticator(),
	SharedSecret = ct:get_config(radius_shared_secret),
	UserPassword = radius_attributes:hide(SharedSecret, Authenticator, PeerPassword),	
	AuthAddress = {127, 0, 0, 1},
	{ok, [{radius, AuthPort, _}]} = application:get_env(ocs, radius_auth_config),
	Socket = ?config(socket, Config), 
	A0 = radius_attributes:new(),
	A1 = radius_attributes:add(?ServiceType, 2, A0),
	A2 = radius_attributes:add(?NasPortId, "wlan1", A1),
	A3 = radius_attributes:add(?NasPortType, 19, A2),
	A4 = radius_attributes:add(?UserName, PeerID, A3),
	A5 = radius_attributes:add(?AcctSessionId, "826005e0", A4),
	A6 = radius_attributes:add(?CallingStationId, CallingStationId, A5),
	A7 = radius_attributes:add(?CalledStationId, CalledStationId, A6),
	A8 = radius_attributes:add(?UserPassword, UserPassword, A7),
	A9 = radius_attributes:add(?NasIdentifier, NasId, A8),
	AccessReqest = #radius{code = ?AccessRequest, id = Id,
			authenticator = Authenticator, attributes = A9},
	AccessReqestPacket= radius:codec(AccessReqest),
	ok = gen_udp:send(Socket, AuthAddress, AuthPort, AccessReqestPacket),
	{ok, {AuthAddress, AuthPort, AccessAcceptPacket}} = gen_udp:recv(Socket, 0),
	#radius{code = ?AccessAccept, id = Id} = radius:codec(AccessAcceptPacket).

out_of_credit() ->
	[{userdata, [{doc, "Send AccessReject response to the peer when balance
			less than 0"}]}].

out_of_credit(Config) ->
	Id = 2,
	NasId = ?config(nas_id, Config),
	CalledStationId = ?config(called_id, Config),
	MAC = "DD:EE:DD:EE:CC:BB",
	MACtokens = string:tokens(MAC, ":"),
	CallingStationId = string:join(MACtokens, "-"),
	PeerID = string:to_lower(lists:append(MACtokens)),
	PeerPassword = ocs:generate_password(),
	ok = ocs:add_subscriber(PeerID, PeerPassword, []),
	Authenticator = radius:authenticator(),
	SharedSecret = ct:get_config(radius_shared_secret),
	UserPassword = radius_attributes:hide(SharedSecret, Authenticator, PeerPassword),	
	AuthAddress = {127, 0, 0, 1},
	{ok, [{radius, AuthPort, _}]} = application:get_env(ocs, radius_auth_config),
	Socket = ?config(socket, Config), 
	A0 = radius_attributes:new(),
	A1 = radius_attributes:add(?ServiceType, 2, A0),
	A2 = radius_attributes:add(?NasPortId, "wlan1", A1),
	A3 = radius_attributes:add(?NasPortType, 19, A2),
	A4 = radius_attributes:add(?UserName, PeerID, A3),
	A5 = radius_attributes:add(?AcctSessionId, "826005e1", A4),
	A6 = radius_attributes:add(?CallingStationId, CallingStationId, A5),
	A7 = radius_attributes:add(?CalledStationId, CalledStationId, A6),
	A8 = radius_attributes:add(?UserPassword, UserPassword, A7),
	A9 = radius_attributes:add(?NasIdentifier, NasId, A8),
	AccessReqest = #radius{code = ?AccessRequest, id = Id, authenticator = Authenticator,
			attributes = A9},
	AccessReqestPacket= radius:codec(AccessReqest),
	ok = gen_udp:send(Socket, AuthAddress, AuthPort, AccessReqestPacket),
	{ok, {AuthAddress, AuthPort, AccessRejectPacket}} = gen_udp:recv(Socket, 0),
	#radius{code = ?AccessReject, id = Id, attributes = AccessRejectData} =
			radius:codec(AccessRejectPacket),
	AccessReject = radius_attributes:codec(AccessRejectData),
	{ok, "Out of Credit"} = radius_attributes:find(?ReplyMessage, AccessReject).

bad_password() ->
	[{userdata, [{doc, "Send AccessReject response to the peer when password 
			not matched"}]}].

bad_password(Config) ->
	Id = 2,
	NasId = ?config(nas_id, Config),
	CalledStationId = ?config(called_id, Config),
	MAC = "DD:EE:DD:EE:DD:CC",
	MACtokens = string:tokens(MAC, ":"),
	CallingStationId = string:join(MACtokens, "-"),
	PeerID = string:to_lower(lists:append(MACtokens)),
	PeerPassword = ocs:generate_password(),
	ok = ocs:add_subscriber(PeerID, PeerPassword, [], 1000),
	Authenticator = radius:authenticator(),
	SharedSecret = ct:get_config(radius_shared_secret),
	BoguesPassowrd = radius_attributes:hide(SharedSecret, Authenticator, "bogus"),	
	AuthAddress = {127, 0, 0, 1},
	{ok, [{radius, AuthPort, _}]} = application:get_env(ocs, radius_auth_config),
	Socket = ?config(socket, Config), 
	A0 = radius_attributes:new(),
	A1 = radius_attributes:add(?ServiceType, 2, A0),
	A2 = radius_attributes:add(?NasPortId, "wlan1", A1),
	A3 = radius_attributes:add(?NasPortType, 19, A2),
	A4 = radius_attributes:add(?UserName, PeerID, A3),
	A5 = radius_attributes:add(?AcctSessionId, "826005e2", A4),
	A6 = radius_attributes:add(?CallingStationId, CallingStationId, A5),
	A7 = radius_attributes:add(?CalledStationId, CalledStationId, A6),
	A8 = radius_attributes:add(?UserPassword, BoguesPassowrd, A7),
	A9 = radius_attributes:add(?NasIdentifier, NasId, A8),
	AccessReqest = #radius{code = ?AccessRequest, id = Id, authenticator = Authenticator,
			attributes = A9},
	AccessReqestPacket= radius:codec(AccessReqest),
	ok = gen_udp:send(Socket, AuthAddress, AuthPort, AccessReqestPacket),
	{ok, {AuthAddress, AuthPort, AccessRejectPacket}} = gen_udp:recv(Socket, 0),
	#radius{code = ?AccessReject, id = Id, attributes = AccessRejectData} =
			radius:codec(AccessRejectPacket),
	AccessReject = radius_attributes:codec(AccessRejectData),
	{ok, "Bad Password"} = radius_attributes:find(?ReplyMessage, AccessReject).

unknown_username() ->
	[{userdata, [{doc, "Send AccessReject response to the peer for unknown username"}]}].

unknown_username(Config) ->
	Id = 3,
	NasId = ?config(nas_id, Config),
	CalledStationId = ?config(called_id, Config),
	MAC = "DD:EE:DD:EE:DD:CC",
	MACtokens = string:tokens(MAC, ":"),
	CallingStationId = string:join(MACtokens, "-"),
	PeerID = string:to_lower(lists:append(MACtokens)),
	PeerPassword = ocs:generate_password(),
	ok = ocs:add_subscriber(PeerID, PeerPassword, [], 1000),
	Authenticator = radius:authenticator(),
	SharedSecret = ct:get_config(radius_shared_secret),
	UserPassword = radius_attributes:hide(SharedSecret, Authenticator, PeerPassword),	
	BogusUserName = "tormentor",
	AuthAddress = {127, 0, 0, 1},
	{ok, [{radius, AuthPort, _}]} = application:get_env(ocs, radius_auth_config),
	Socket = ?config(socket, Config), 
	A0 = radius_attributes:new(),
	A1 = radius_attributes:add(?ServiceType, 2, A0),
	A2 = radius_attributes:add(?NasPortId, "wlan1", A1),
	A3 = radius_attributes:add(?NasPortType, 19, A2),
	A4 = radius_attributes:add(?UserName, BogusUserName, A3),
	A5 = radius_attributes:add(?AcctSessionId, "826005e3", A4),
	A6 = radius_attributes:add(?CallingStationId, CallingStationId, A5),
	A7 = radius_attributes:add(?CalledStationId, CalledStationId, A6),
	A8 = radius_attributes:add(?UserPassword, UserPassword, A7),
	A9 = radius_attributes:add(?NasIdentifier, NasId, A8),
	AccessReqest = #radius{code = ?AccessRequest, id = Id, authenticator = Authenticator,
			attributes = A9},
	AccessReqestPacket= radius:codec(AccessReqest),
	ok = gen_udp:send(Socket, AuthAddress, AuthPort, AccessReqestPacket),
	{ok, {AuthAddress, AuthPort, AccessRejectPacket}} = gen_udp:recv(Socket, 0),
	#radius{code = ?AccessReject, id = Id, attributes = AccessRejectData} =
			radius:codec(AccessRejectPacket),
	AccessReject = radius_attributes:codec(AccessRejectData),
	{ok, "Unknown Username"} = radius_attributes:find(?ReplyMessage, AccessReject).

