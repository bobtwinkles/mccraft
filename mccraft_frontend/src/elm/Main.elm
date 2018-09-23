port module Main exposing (Model, init, main)

import Array exposing (Array)
import Browser
import Debug
import Dict exposing (Dict)
import Graph exposing (Edge, Graph, Node, NodeId)
import Html exposing (..)
import Html.Attributes exposing (alt, class, id, placeholder, src, type_)
import Html.Events exposing (..)
import Html.Keyed
import Http
import IntDict
import ItemRendering exposing (itemLine, urlForItem)
import Json.Decode as Decode
import Json.Encode as Encode
import List.Extra as LE
import Messages
import PrimaryModel exposing (..)
import Random
import RecipeModal as RM
import Regex
import Search
import Url.Builder as Url



-- import Visualization.Force as Force exposing (State)
-- import Visualization.Scale as Scale exposing (SequentialScale)


main =
    Browser.element
        { init = init
        , update = update
        , subscriptions = subscriptions
        , view = view
        }



-- Ports


graphEdgeEncoder : Graph.Edge GraphEdge -> Encode.Value
graphEdgeEncoder edge =
    Encode.object
        [ ( "source", Encode.int edge.from )
        , ( "target", Encode.int edge.to )
        , ( "id", Encode.int edge.label.id )
        ]


graphNodeEncoder : Graph.Node CraftingGraphNode -> Encode.Value
graphNodeEncoder ent =
    Encode.object
        [ ( "id", Encode.int ent.id )
        , ( "name", Encode.string ent.label.name )
        , ( "imgUrl", Encode.string ent.label.imgUrl )
        ]


port edgeOut : Encode.Value -> Cmd msg


port nodeOut : Encode.Value -> Cmd msg



-- Model


type alias CraftingGraphNode =
    { name : String, imgUrl : String }


mkGraphNode : Item -> Graph.Node CraftingGraphNode
mkGraphNode item =
    Graph.Node item.id (CraftingGraphNode item.itemName (urlForItem item))


type alias GraphEdge =
    { id : Int }


type CurrentModal
    = NoModal
    | RecipeModal RM.Model


type alias Model =
    { graph : Graph CraftingGraphNode GraphEdge
    , searchBar : Search.Model
    , errorMessage : Maybe String
    , modal : CurrentModal
    }


init : () -> ( Model, Cmd Messages.Msg )
init _ =
    ( Model Graph.empty Search.mkModel Nothing NoModal, Cmd.none )



-- Update


updateModelForError : Model -> String -> Model
updateModelForError model err =
    { model | errorMessage = Just err }


update : Messages.Msg -> Model -> ( Model, Cmd Messages.Msg )
update msg model =
    Debug.log ("Processing message " ++ Debug.toString msg)
        (case msg of
            Messages.SearchMsg x ->
                let
                    ( newBar, cmd ) =
                        Search.update x model.searchBar
                in
                ( { model | searchBar = newBar }, cmd )

            Messages.GridMsg (Messages.AddItem item) ->
                let
                    itemNode =
                        mkGraphNode item

                    newGraph =
                        Graph.insert
                            { node = itemNode
                            , incoming = IntDict.empty
                            , outgoing = IntDict.empty
                            }
                            model.graph
                in
                ( { model | searchBar = Search.mkModel, graph = newGraph }
                , nodeOut (graphNodeEncoder itemNode)
                )

            Messages.PopRecipeModalFor item ->
                update (Messages.RecipeModalMsg Messages.SendPartialRequest)
                    { model
                        | modal = RecipeModal <| RM.mkModel item
                        , searchBar = Search.mkModel
                    }

            Messages.RecipeModalMsg rmm ->
                case model.modal of
                    RecipeModal modal ->
                        let
                            ( newModal, cmd ) =
                                RM.update rmm modal
                        in
                        ( { model | modal = RecipeModal newModal }, cmd )
                    _ ->
                        ( model, Cmd.none )


            Messages.ExitModal ->
                ( { model | modal = NoModal }, Cmd.none )

            --- TODO: display an error to the user. Build infrastructure like Flask's flashes?
            Messages.FlashError emsg ->
                ( updateModelForError model emsg, Cmd.none )
        )



-- VIEW


debugPane : Model -> Html Messages.Msg
debugPane model =
    let
        baseContent =
            [ text (Graph.toString (\v -> Just v.name) (\e -> Just (Debug.toString e.id)) model.graph)
            ]

        errorContent =
            case model.errorMessage of
                Nothing ->
                    []

                Just msg ->
                    [ br [] [], code [] [ text msg ] ]
    in
    div [ class "debug-pane" ] (baseContent ++ errorContent)


matchColon : Regex.Regex
matchColon =
    Maybe.withDefault Regex.never <| Regex.fromString ":"


view : Model -> Html Messages.Msg
view model =
    let
        modalView =
            case model.modal of
                RecipeModal modal ->
                    [ RM.view modal ]

                NoModal ->
                    []
    in
    div []
        ([ debugPane model
         , Search.view model.searchBar
         ]
            ++ modalView
        )



-- Subscriptions


subscriptions : Model -> Sub Messages.Msg
subscriptions model =
    Sub.none
