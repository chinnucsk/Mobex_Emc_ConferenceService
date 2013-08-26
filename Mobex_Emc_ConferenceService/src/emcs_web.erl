%% @author Mochi Media <dev@mochimedia.com>
%% @copyright 2010 Mochi Media <dev@mochimedia.com>

%% @doc Web server for emcs.

-module(emcs_web).
-author("Mochi Media <dev@mochimedia.com>").

-export([start/1, stop/0, loop/2]).

%% MySQL Configuration
-define(MYSQL_SERVER, "localhost").
-define(MYSQL_USER, "root").
-define(MYSQL_PASSWD, "password").
-define(MYSQL_DB, "emc").
-define(MYSQL_PORT, 3306).

-record(sessions, {id, uid, status,flag,mid}).
-record(meetings, { mid, status}).

%% External API

start(Options) ->
    {DocRoot, Options1} = get_option(docroot, Options),
    Loop = fun (Req) ->
                   ?MODULE:loop(Req, DocRoot)
           end,
    % start mysql
    application:start(emysql),
    emysql:add_pool(myjqrealtime, 1, ?MYSQL_USER, ?MYSQL_PASSWD, ?MYSQL_SERVER, ?MYSQL_PORT, ?MYSQL_DB, utf8),
	
    mochiweb_http:start([{name, ?MODULE}, {loop, Loop} | Options1]).

stop() ->
    mochiweb_http:stop(?MODULE).


%% Check session util
check_session(Uid) ->

    %% Check session
    CheckSession = emysql:execute(myjqrealtime, 
        lists:concat([
            "SELECT * FROM emc_user_meeting WHERE flag=1 and uid = ", 
            emysql_util:quote(getclean(Uid)),
            " LIMIT 1"
        ]
    )),

    %% Convert to records
    Records = emysql_util:as_record(CheckSession, sessions, record_info(fields, sessions)),

    %% Check existence & return user_id if possible
    if
        length(Records) == 1 ->
            %% Get UserId of element
            [{_, Id,_, _,_, _}] = [Rec || Rec <- Records],
            {integer_to_list(Id)};
        true ->
            false
    end.

check_have_new_conference(Uid) ->
    %% Check session
    CheckSession = emysql:execute(myjqrealtime, 
        lists:concat([
            "SELECT * FROM emc_user_meeting WHERE status=0 and flag=0 and uid = ", 
            emysql_util:quote(getclean(Uid)),
            " LIMIT 1"
        ]
    )),

    %% Convert to records
    Records = emysql_util:as_record(CheckSession, sessions, record_info(fields, sessions)),

    %% Check existence & return true if possible
    if
        length(Records) == 1 ->
            true;
        true ->
            false
    end.

loop(Req, DocRoot) ->
    "/" ++ Path = Req:get(path),
    try
        case Req:get(method) of
            Method when Method =:= 'GET'; Method =:= 'HEAD' ->
                case Path of
                "test/" ++ Id ->
                    Response = Req:ok({"text/html; charset=utf-8",
                                      [{"Server","Mochiweb-Test"}],
                                      chunked}),
					feed(Response, Id, 1);
					"hello" ->
						QueryStringData = Req:parse_qs(),
						Username = proplists:get_value("username", QueryStringData, "Anonymous"),
						Req:respond({200, [{"Content-Type", "text/plain"}],
									 "Hello " ++ Username ++ "!\n"});
					_ ->
						Req:serve_file(Path, DocRoot)
				end;
            'POST' ->
                case Path of
                    _ ->
                        Req:not_found()
                end;
            _ ->
                Req:respond({501, [], []})
        end
    catch
        Type:What ->
			%%case Path of
            %%    "test/" ++ Uid ->
			%%   emysql:prepare(my_stmt, <<"delete from emc_user_meeting where uid =?">>),
			%%   emysql:execute(myjqrealtime, my_stmt, [Uid])
			%%end,
            Report = ["web request failed",
                      {path, Path},
                      {type, Type}, {what, What},
                      {trace, erlang:get_stacktrace()}],
            error_logger:error_report(Report),
            %% NOTE: mustache templates need \ because they are not awesome.
            Req:respond({500, [{"Content-Type", "text/plain"}],
                         "request failed, sorry\n"})
    end.

feed(Response, Id, N) ->
    receive
        %{router_msg, Msg} ->
        %    Html = io_lib:format("Recvd msg #~w: '~s'<br/>", [N, Msg]),
        %    Response:write_chunk(Html);
    after 1000 ->
					case check_session(Id) of
						{Rid} ->%%login in before
                              
							    case check_have_new_conference(Id) of
									true->
										Result = emysql:execute(myjqrealtime,
																lists:concat([
																			  "SELECT mid,status FROM emc_user_meeting WHERE flag=0 and  uid = ",
																			  emysql_util:quote(getclean(Id)),
																			  " and id>",
																			  emysql_util:quote(getNumber(Rid))
																			 ]
																			)),
										JSON = emysql_util:as_json(Result),
										Myjson = mochijson2:encode([<<"new">>,1|JSON]),
										Response:write_chunk(Myjson);
									false->
										Result = emysql:execute(myjqrealtime,
																lists:concat([
																			  "SELECT mid,status FROM emc_user_meeting WHERE flag=0 and   uid = ",
																			  emysql_util:quote(getclean(Id)),
																			  ""
																			 ]
																			)),
										JSON = emysql_util:as_json(Result),
										Myjson = mochijson2:encode([<<"new">>,0|JSON]),
										Response:write_chunk(Myjson)
								end;
						false ->%%not login in before
                               emysql:prepare(my_stmt, <<"delete from emc_user_meeting where uid =?">>),
							   emysql:execute(myjqrealtime, my_stmt, [Id]),
							   emysql:prepare(my_stmt, <<"INSERT INTO emc_user_meeting SET uid =?, flag=?">>),
							   emysql:execute(myjqrealtime, my_stmt, [Id,1])
					end,
           Response:write_chunk("|")
    end,
    feed(Response, Id, N+1).

%% Internal API

get_option(Option, Options) ->
    {proplists:get_value(Option, Options), proplists:delete(Option, Options)}.


%% Get Value or "" if undefined
getclean(X) when X /= undefined ->
    X;
getclean(_) ->
    "".

getNumber(X) when X /= undefined ->
    X;
getNumber(_) ->
    0.


%%
%% Tests
%%
-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").

you_should_write_a_test() ->
    ?assertEqual(
       "No, but I will!",
       "Have you written any tests?"),
    ok.

-endif.