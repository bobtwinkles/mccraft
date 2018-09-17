port module Main exposing (Model, init, main)

import Browser
import Debug
import Graph exposing (Edge, Graph, Node, NodeId)
import Html exposing (..)
import Html.Events exposing (..)
import Html.Keyed
import IntDict
import Json.Decode as Decode exposing (Decoder)
import Json.Decode.Pipeline as Pipeline exposing (required)
import Json.Encode as Encode
import Random



-- import Visualization.Force as Force exposing (State)
-- import Visualization.Scale as Scale exposing (SequentialScale)


main =
    Browser.element
        { init = init
        , update = update
        , subscriptions = subscriptions
        , view = view
        }



-- Communication structures


type ItemType
    = ItemStack
    | Fluid
    | UnknownType


matchItemType : String -> ItemType
matchItemType x =
    case x of
        "Item" ->
            ItemStack

        "Fluid" ->
            Fluid

        _ ->
            UnknownType


itemType : Decoder ItemType
itemType =
    Decode.map matchItemType Decode.string


type alias ItemSpec =
    { id : Int
    , itemName : String
    , minecraftId : String
    , ty : ItemType
    , quantity : Int
    }


itemSpecDecoder : Decoder ItemSpec
itemSpecDecoder =
    Decode.succeed ItemSpec
        |> required "item_id" Decode.int
        |> required "item_name" Decode.string
        |> required "minecraft_id" Decode.string
        |> required "ty" itemType
        |> required "quantity" Decode.int


type alias Item =
    { id : Int
    , itemName : String
    , minecraftId : String
    , ty : ItemType
    }


itemDecoder : Decoder Item
itemDecoder =
    Decode.succeed Item
        |> required "item_id" Decode.int
        |> required "item_name" Decode.string
        |> required "minecraft_id" Decode.string
        |> required "ty" itemType



-- Ports


graphEdgeEncoder : Graph.Edge GraphEdge -> Encode.Value
graphEdgeEncoder edge =
    Encode.object
        [ ( "source", Encode.int edge.from )
        , ( "target", Encode.int edge.to )
        , ( "id", Encode.int edge.label.id )
        ]


graphNodeEncoder : Graph.Node Entity -> Encode.Value
graphNodeEncoder ent =
    Encode.object
        [ ( "id", Encode.int ent.id )
        , ( "name", Encode.string ent.label.name )
        ]


graphEncoder : Graph Entity GraphEdge -> Encode.Value
graphEncoder graph =
    Encode.object
        [ ( "edges", Encode.list graphEdgeEncoder (Graph.edges graph) )
        , ( "nodes", Encode.list graphNodeEncoder (Graph.nodes graph) )
        ]


port edgeOut : Encode.Value -> Cmd msg


port nodeOut : Encode.Value -> Cmd msg



-- Model


type alias Entity =
    { rank : Int, name : String }


mkGraphNode : NodeId -> Int -> String -> Graph.Node Entity
mkGraphNode id rank name =
    Graph.Node id (Entity rank name)


type alias GraphEdge =
    { id : Int }


type alias Model =
    { graph : Graph Entity GraphEdge }


init : () -> ( Model, Cmd Msg )
init _ =
    ( Model Graph.empty, Cmd.none )



-- Update


type RandLinkMsg
    = CreateLink
    | ResultLink ( Int, Int )


createLinkGenerator : Int -> Random.Generator ( Int, Int )
createLinkGenerator numNodes =
    Random.pair (Random.int 0 (numNodes - 1)) (Random.int 0 (numNodes - 2))


type RandNodeMsg
    = CreateNode
    | ResultNode Int


createNodeGenerator : Int -> Random.Generator Int
createNodeGenerator numNodes =
    Random.int numNodes (numNodes + 1)


type Msg
    = NewRandomLink RandLinkMsg
    | NewRandomNode RandNodeMsg


updateLinkMsg : RandLinkMsg -> Graph Entity GraphEdge -> ( Graph Entity GraphEdge, Cmd Msg )
updateLinkMsg msg model =
    case msg of
        CreateLink ->
            ( model, Random.generate (\x -> NewRandomLink (ResultLink x)) (createLinkGenerator (Graph.size model)) )

        ResultLink ( source, dest ) ->
            let
                target =
                    if dest >= source then
                        modBy (dest + 1) (Graph.size model)

                    else
                        dest

                edgeLabel =
                    { id = List.length (Graph.edges model)
                    }

                newGraph =
                    Graph.update source
                        (\x ->
                            case x of
                                Just ({ node, incoming, outgoing } as ctx) ->
                                    Just { ctx | outgoing = IntDict.insert target edgeLabel outgoing }

                                Nothing ->
                                    Nothing
                        )
                        model

                newEdge =
                    Graph.Edge source target edgeLabel
            in
            ( newGraph, edgeOut (graphEdgeEncoder newEdge) )


updateNodeMsg : RandNodeMsg -> Graph Entity GraphEdge -> ( Graph Entity GraphEdge, Cmd Msg )
updateNodeMsg msg model =
    case msg of
        CreateNode ->
            ( model, Random.generate (\x -> NewRandomNode (ResultNode x)) (createNodeGenerator (Graph.size model)) )

        ResultNode n ->
            let
                newNode =
                    mkGraphNode (Graph.size model) 0 (Debug.toString n)

                newGraph =
                    Graph.insert
                        { node = newNode
                        , incoming = IntDict.empty
                        , outgoing = IntDict.empty
                        }
                        model
            in
            ( newGraph, nodeOut (graphNodeEncoder newNode) )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    Debug.log ("Processing message " ++ Debug.toString msg)
        (case msg of
            NewRandomLink linkMsg ->
                let
                    ( newGraph, linkResp ) =
                        updateLinkMsg linkMsg model.graph
                in
                ( { model | graph = newGraph }, linkResp )

            NewRandomNode nodeMsg ->
                let
                    ( newGraph, nodeResp ) =
                        updateNodeMsg nodeMsg model.graph
                in
                ( { model | graph = newGraph }, nodeResp )
        )



-- VIEW


pageStructure : Html Msg -> Html Msg
pageStructure inner =
    div []
        [ inner ]


view : Model -> Html Msg
view model =
    div []
        [ button [ onClick (NewRandomLink CreateLink) ] [ text "New random link" ]
        , button [ onClick (NewRandomNode CreateNode) ] [ text "New random node" ]
        , text (Graph.toString (\v -> Just v.name) (\e -> Just (Debug.toString e.id)) model.graph)
        ]



-- Subscriptions


subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.none
