-module(content).
-behaviour(gen_server).

-define(CONTENT_ROOT_DIR, "/home/toraritte/clones/phone-service/content-root/").
-define(CONTENT_ROOT, {category, 0, "Main category"}).

-export(
   [ start/0
   , start_link/0

   % gen_server callbacks
   , init/1
   , handle_call/3
   % , handle_cast/2
   % , terminate/2

   % private functions
   , make_content_graph/0
   , refresh_content_graph/1
   , realize/0

   , get_vertex/2
   , current/1
   , update_history/2
   ]).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% gen_server callbacks                                               %%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

start_link() ->
    {ok, Pid} = gen_server:start_link({local, ?MODULE}, ?MODULE, [], []),
    Pid.

start() ->
    {ok, Pid} = gen_server:start({local, ?MODULE}, ?MODULE, [], []),
    Pid.

init(_Args) ->
    Graph = make_content_graph(),
    digraph:add_vertex(Graph, history, []),
    % Necessary because ?CONTENT_ROOT gets written to the metafile, but that tuple is going to be changed when building the graph (and reading back from the file system).
    ContentRoot =
        lists:keyfind(0, 2, digraph:vertices(Graph)),
    digraph:add_edge
        ( Graph
        , current         % edge name
        , history         % from vertex
        , ContentRoot   % to
        , [ContentRoot] % label, moonlighting as history stack
        ),

    {ok, Graph}.

%           request,      from,        state
handle_call({Action, Direction}, _From, Graph)
  when Direction =:= parent       % \
     ; Direction =:= first        % |
     ; Direction =:= last         % |
     ; Direction =:= next         % | Vertex
     ; Direction =:= prev         % |
     ; Direction =:= content_root % |
     ; Direction =:= current      % /
     ; Direction =:= children     %   [ Vertex ]
->
    { reply
    , process_action(Graph, Action, Direction)
    , Graph
    };

handle_call(_Command, _From, Graph) ->
    {reply, invalid_action, Graph}.

% Direction -> Vertex
process_action(Graph, get, current) ->
    current(Graph);

% Direction -> Vertex
process_action(_Graph, get, content_root) ->
    ?CONTENT_ROOT;

%! Direction -> [ Vertex ]
process_action(Graph, get, children) ->
    get_vertex(Graph, child);

process_action(Graph, get, Direction) ->
    % TODO These are the only 2 options here, and if this does crash it means there's a logical error somewhere in this module.
    case get_vertex(Graph, Direction) of
        % This means that the current vertex does not have that specific direction. E.g., articles won't have child, first, last edges.
        [] ->
            invalid_action;
        [Vertex] ->
            Vertex
    end;

process_action(Graph, go_to, Direction)
  when Direction =:= children;
       Direction =:= invalid_action
->
    invalid_action;

process_action(Graph, go_to, Vertex)
  when erlang:is_tuple(Vertex)
->
    update_history(Graph, Vertex),
    Vertex;

process_action(Graph, go_to, Direction) ->
    % TODO
    % http://blog.sigfpe.com/2006/08/you-could-have-invented-monads-and.html
    Vertex = process_action(Graph, get, Direction),
    process_action(Graph, go_to, Vertex).

% handle_cast(reload_db = Request, _PhoneNumberSet) ->
%     log(debug, [reload_db, Request]),
%     NewPhoneNumberSet = load_phone_numbers(),
%     {noreply, NewPhoneNumberSet}.

% terminate(Reason, _Graph) ->
%     log(debug, [terminate_making_sure, Reason]),
%     filog:remove_singleton_handler(?MODULE).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Private functions                                                  %%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% CONTENT GRAPH {{-

% TODO Depends on the internal representation.
%      Refactor when the web service is ready (or usable).
make_content_graph() ->
    make_content_graph(?CONTENT_ROOT_DIR).

make_content_graph(ContentRootDir) -> % {{-
    Graph =
        digraph:new([cyclic, protected]),
    % {category, 0, "Main category"}
    RootMeta = get_meta(ContentRootDir),
    digraph:add_vertex(Graph, RootMeta),
    % NOTE Theoretically it is not necessary because `get_vertex/2` returns [] for non-existing edges
    % [ digraph:add_edge
    %     ( Graph
    %     , {Edge, RootMeta}
    %     , RootMeta
    %     , RootMeta
    %     , []
    %     )
    % || Edge <- [parent, prev, next]
    % ],
    do_make(Graph, ContentRootDir),
    Graph.
% }}-

refresh_content_graph(Graph) ->
    refresh_content_graph(Graph, ?CONTENT_ROOT_DIR).

refresh_content_graph(Graph, ContentRoot) ->
    digraph:delete(Graph),
    make_content_graph(ContentRoot).

add_hierarcy_edges(Graph, ParentMeta, Meta) -> % {{-
    digraph:add_edge(
      Graph,          % digraph
      {child, Meta},  % edge
      ParentMeta,     % from vertex
      Meta,           % to vertex
      []              % label
    ),
    digraph:add_edge(
      Graph,          % digraph
      {parent, Meta}, % edge
      Meta,           % from vertex
      ParentMeta,     % to vertex
      []              % label
    ).
% }}-

add_next_edge(Graph, From, To) ->
    digraph:add_edge(Graph, {next, To}, From, To, []).

add_prev_edge(Graph, From, To) ->
    digraph:add_edge(Graph, {prev, To}, From, To, []).

add_meta_to_path(_ContentType, _Dir, "meta.erl") -> % {{-
    % logger:notice("meta"),
    false;

add_meta_to_path(ContentType, Dir, Path) ->
    % logger:notice(#{path => Path, ct => ContentType}),
    FullPath = filename:join(Dir, Path),
    Meta =
        case ContentType of
               category -> get_meta(FullPath);
            % TODO the anchor text should hold the name of the article's title
            % TODO previous todo also implies that each article should alsw have a metafile, requiring extensive rewrite
            publication -> {article, FullPath, #{ anchor => "article" }}
        end,
    {true, {Meta, FullPath}}.
% }}-

do_make(Graph, Dir) ->
    case file:list_dir(Dir) of
        {error, _} ->
            done;
        {ok, List} ->
            OrderedDirList =
                ordsets:from_list(List),
            % If ContentType =:= publication then DirList will consist entirely of files (meta.erl + audio files)
            {ContentType, _, _} = Meta =
                get_meta(Dir),
            MetaPathTuples =
                lists:filtermap(
                  % ((curry(fun add_meta_to_path/3))(ContentType))(Dir),
                  fun(Path) -> add_meta_to_path(ContentType, Dir, Path) end,
                  OrderedDirList
                ),
            do_dirlist(Graph, Meta, [first|MetaPathTuples])
    end.

do_dirlist(_Graph, _ParentMeta, []) ->
    done;

do_dirlist(Graph, ParentMeta, [{_, "meta.erl"}|Rest]) ->
    do_dirlist(Graph, ParentMeta, Rest);

do_dirlist(_Graph, _ParentMeta, [first]) ->
    empty_dir;

do_dirlist( % {{-
  Graph,
  ParentMeta,
  [ first
  , {Meta, FullPath} = MetaPath
  | Rest
  ]
) ->
    logger:notice(#{ first => MetaPath }),
    % add_vertex_and_parent_edge(Graph, ParentMeta, Meta, first),
    % digraph:add_vertex(Graph, Meta, first),
    digraph:add_vertex(Graph, Meta),
    digraph:add_edge(Graph, {first, Meta}, ParentMeta, Meta, []),
    add_hierarcy_edges(Graph, ParentMeta, Meta),
    % add_vertex_and_parent_edge(Graph, ParentMeta, Meta),
    do_make(Graph, FullPath),
    do_dirlist(Graph, ParentMeta, [MetaPath|Rest]);
% }}-

do_dirlist( % {{-
  Graph,
  ParentMeta,
  [ {MetaA, _} = M
  , {MetaB, FullPathB} = MetaPath
  | Rest
  ]
) ->
    logger:notice(#{ metapath_a => M, metapath_b => MetaPath}),
    % { NewDirList
    % , VertexBLabel
    % } =
    % add_vertex_and_parent_edge(Graph, ParentMeta, MetaB),
    % digraph:add_vertex(Graph, MetaB, VertexBLabel),
    digraph:add_vertex(Graph, MetaB),
    add_hierarcy_edges(Graph, ParentMeta, MetaB),
    add_prev_edge(Graph, MetaB, MetaA),
    add_next_edge(Graph, MetaA, MetaB),
    do_make(Graph, FullPathB),

    NewDirList =
        case Rest =:= [] of
            true ->
                digraph:add_edge(Graph, {last, MetaB}, ParentMeta, MetaB, []),
                [];
            false ->
                [MetaPath|Rest]
        end,
    do_dirlist(Graph, ParentMeta, NewDirList).
% }}-
% }}-

% Graph -> Vertex
current(Graph) ->
    {current, history, Current, _History} =
        digraph:edge(Graph, current),
    Current.

% Graph -> Direction -> List Vertex
% TODO Direction is misleading because it means smth else in different contexts
% Direction = parent | next | prev | first | last | child
get_vertex(Graph, Direction) ->
    Current = current(Graph),

    EdgeResults =
        [  digraph:edge(Graph, Edge)
        || Edge <- digraph:out_edges(Graph, Current),
                   erlang:element(1, Edge) =:= Direction
        ],

    [  Vertex
    || { {Direction, _} % edge
       , _              % from
       , Vertex         % to
       , []             % edge label
       }
       <- EdgeResults
    ].

% Graph -> Vertex -> current | noop
update_history(Graph, With) ->
    { current % edge name
    , history % from
    , Current % to
    , History % edge label
    } =
        digraph:edge(Graph, current),

    case With =:= Current of
        true ->
            noop;
        false ->
            digraph:del_edge(Graph, current),
            digraph:add_edge
                ( Graph
                , current        % edge name
                , history        % from vertex
                , With           % to
                , [With|History] % label, moonlighting as history stack
                )
    end.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% INTERNAL MODEL OF THE YET TO BE BUILT ACCESS NEWS WEB SERVICE      %%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% {{-
% NOTE for the resulting graph when determining neighbours:
% to avoid excessive amount of connections (and facing the problems updating them would cause), it will be done by finding the parent category, and adding/subtracting one from their "ID".
% The publication guide below is just a representation of future data of the yet-to-be-implemented core web service, and its data may not contain such IDs, but that could be done on this end by ordering and adding that via a script.

publication_guide() -> % {{-
    [ { {category, 1, "Store sales advertising"}
      , [ { {category, 1, "Grocery stores"}
          , [ {publication, 1, "Safeway"}
            , {publication, 2, "Raley's"}
            , {publication, 3, "La Superior"}
            , {publication, 4, "Food source"}
            , {publication, 5, "Savemart"}
            , {publication, 6, "Foods Co"}
            , {publication, 7, "Trader Joe's"}
            , {publication, 8, "Sprouts"}
            , {publication, 9, "Lucky Supermarkets"}
            ]
          }
        , { {category, 2, "Drug stores"}
          , [ {publication, 1, "CVS"}
            , {publication, 2, "Rite Aid"}
            , {publication, 3, "Walgreen's"}
            ]
          }
        , { {category, 3, "Discount stores"}
          , [ {publication, 1, "Target"}
            , {publication, 2, "Walmart"}
            ]
          }
        ]
      }

    , { {category, 2, "Sacramento newspapers and magazines"}
      , [ { {category, 1, "Sacramento newspapers"}
          , [ {publication, 1, "Sacramento Bee"}
            , {publication, 2, "Sacramento News & Review"}
            , {publication, 3, "Sacramento Press"}
            , {publication, 4, "Sacramento Business Journal"}
            , {publication, 5, "East Sacramento News by Valley Community Newspapers"}
            , {publication, 6, "The Land Park News by Valley Community Newspapers"}
            , {publication, 7, "The Pocket News by Valley Community Newspapers"}
            ]
          }
        , { {category, 2, "Sacramento magazines"}
          , [ {publication, 1, "Comstocks"}
            , {publication, 2, "SacTown"}
            , {publication, 3, "Sacramento Magazine"}
            ]
          }
        ]
      }

    , { {category, 3, "Greater Sacramento area newspapers"}
      , [ {publication, 1, "Carmichael Times"}
        , {publication, 2, "Arden Carmichael News"}
        , {publication, 3, "California Kids"}
        , {publication, 4, "Davis Enterprise"}
        , {publication, 5, "Roseville Press Tribune"}
        , {publication, 6, "Woodland Daily Democrat"}
        , {publication, 7, "Carmichael Times"}
        , {publication, 8, "Auburn Journal"}
        , {publication, 9, "Grass Valley-Nevada City Union"}
        , {publication, 10, "Arden Carmichael News by Valley Community Newspapers"}
        , {publication, 11, "El Dorado County Mountain Democrat"}
        ]
      }

    , { {category, 4, "Central California newspapers"}
      , [ {publication, 1, "Modesto Bee"}
        , {publication, 2, "Stockton Record"}
        ]
      }

    , { {category, 5, "San Francisco and Bay Area newspapers"}
      , [ {publication, 1, "Vallejo Times Herald"}
        , {publication, 2, "Santa Rosa Press Democrat"}
        , {publication, 3, "SF Gate"}
        , {publication, 4, "San Francisco Bay Guardian"}
        , {publication, 5, "East Bay Times"}
        , {publication, 6, "SF Weekly"}
        , {publication, 7, "KQED Bay Area Bites"}
        ]
      }

    , { {category, 6, "Northern California newspapers"}
      , [ {publication, 1, "Fort Bragg Advocate News"}
        , {publication, 2, "The Mendocino Beacon"}
        , {publication, 3, "Humboldt Senior Resource Center's Senior News"}
        , {publication, 4, "North Coast Journal"}
        , {publication, 5, "Mad River Union"}
        , {publication, 6, "Eureka Times Standard"}
        , {publication, 7, "Ferndale Enterprise"}
        ]
      }
    ].
% }}-

write_meta_file
  ( {ContentType, Selection, AnchorText} = _Category
  , Dir
  )
-> % {{-
    MetaFilePath =
        filename:join(Dir, metafile_name()),
    Content =
        stringify(
          { ContentType
          , Selection
          , #{ anchor => AnchorText }
          }
        ),
    file:write_file(
      MetaFilePath,
      Content ++ "."
    ),
    Dir.
% }}-

metafile_name() ->
    "meta.erl".

get_meta(CategoryDir) -> % {{-
    MetaPath =
        filename:join(
          CategoryDir,
          metafile_name()
        ),
    {ok, Meta} =
        file:script(MetaPath),
    Meta.
% }}-

list_category_entries(CategoryDir) -> % {{-
    { ok
    , SubCategoryDirectories
    } =
        file:list_dir(CategoryDir),
    MetaList =
        lists:map(
          fun(SubDir) ->
              MetaPath =
                  filename:join([CategoryDir, SubDir, metafile_name()]),
              {ok, {_, N, SubCategory} } =
                  file:script(MetaPath),

              "Press "
              ++ integer_to_list(N)
              ++ " for "
              ++ SubCategory
              ++ "."
          end,
          SubCategoryDirectories -- [metafile_name()]
        ),
    ordsets:from_list(MetaList).
% }}-

make_dir_and_meta_file({_, N, _} = Category, Path) -> % {{-
    Dir =
        filename:join(
          Path,
          integer_to_list(N)
        ),
    file:make_dir(Dir),
    write_meta_file(Category, Dir).
% }}-

realize() ->
    realize(?CONTENT_ROOT_DIR).

realize(ContentRoot) -> % {{-
    case file:make_dir(ContentRoot) of
        ok ->
            write_meta_file(
              ?CONTENT_ROOT,
              ContentRoot
            ),
            realize(publication_guide(), ContentRoot);
        {error, _} = Error ->
            Error
    end.
% }}-

realize( % {{-
  [ { {category, _, _} = Category
    , [_|_] = SubCategories
    }
    | Rest
  ],
  Path
)
->
    NewPath =
        make_dir_and_meta_file(Category, Path),

    realize(SubCategories, NewPath),
    realize(Rest, Path);
% }}-

realize([], _Path) ->
    done;

realize([{publication, _, _} = Publication | Rest], Path) ->
    make_dir_and_meta_file(Publication, Path),
    realize(Rest, Path).

add_recordings(FromDir, ToDir) -> % {{-
    {ok, FileList} =
        file:list_dir(FromDir),
    MoveAndRenameFile =
        fun (File) ->
            FromPath =
                filename:join(FromDir, File),
            NewBaseFileName =
                integer_to_list(os:system_time()),
            OldFileExt =
                filename:extension(File),
            ToPath =
                filename:join(
                  ToDir,
                  NewBaseFileName ++ OldFileExt
                ),
            file:copy(FromPath, ToPath)
        end,
    lists:foreach(
      MoveAndRenameFile,
      FileList
    ).
% }}-

stringify(Term) ->
    R = io_lib:format("~p",[Term]),
    lists:flatten(R).
% }}-

% log(Level, ValueList) ->
%     filog:log(Level, ?MODULE, ValueList).

% vim: set fdm=marker:
% vim: set foldmarker={{-,}}-:
% vim: set nowrap:
