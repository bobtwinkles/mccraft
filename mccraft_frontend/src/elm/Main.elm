port module Main exposing (Model, init, main)

import Browser
import Debug
import Graph exposing (Edge, Graph, Node, NodeId)
import Html exposing (..)
import Html.Attributes exposing (alt, class, id, placeholder, src, type_)
import Html.Events exposing (..)
import IntDict
import ItemRendering exposing (itemLine, urlForItem)
import Json.Encode as Encode
import Messages
import PrimaryModel exposing (..)
import RecipeModal as RM
import RefineModal as RFM
import Regex
import Search
import Set exposing (Set)
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
-- graphEdgeEncoder : Graph.Edge CraftingGraphEdge -> Encode.Value
-- graphEdgeEncoder edge =
--     Encode.object
--         [ ( "source", Encode.int edge.from )
--         , ( "target", Encode.int edge.to )
--         , ( "id", Encode.int edge.label.id )
--         ]
--
--
-- graphNodeEncoder : Graph.Node CraftingGraphNode -> Encode.Value
-- graphNodeEncoder ent =
--     Encode.object
--         [ ( "id", Encode.int ent.id )
--         , ( "name", Encode.string ent.label.name )
--         , ( "imgUrl", Encode.string ent.label.imgUrl )
--         ]


port edgeOut : Encode.Value -> Cmd msg


port nodeOut : Encode.Value -> Cmd msg



-- Model


type alias ItemNode =
    { name : String, imgUrl : String }


type alias RecipeNode =
    { machineName : String }


type CraftingGraphNode
    = ItemGraphNode ItemNode
    | RecipeGraphNode RecipeNode


mkItemNode : Item -> Graph.Node CraftingGraphNode
mkItemNode item =
    Graph.Node item.id (ItemGraphNode <| ItemNode item.itemName (urlForItem item))


mkRecipeNode : CompleteRecipe -> Graph.Node CraftingGraphNode
mkRecipeNode recipe =
    Graph.Node -recipe.recipeId (RecipeGraphNode <| RecipeNode recipe.machineName)


type alias CraftingGraphEdge =
    -- Identifier for this edge
    { id : Int

    -- How much "to" is produced from each "from"
    , production : Int
    }


type CurrentModal
    = NoModal
    | RecipeModal RM.Model
    | RefinementModal RFM.Model


type alias Model =
    { graphContents :
        { graph : Graph CraftingGraphNode CraftingGraphEdge
        , items : Set Int
        }
    , searchBar : Search.Model
    , errorMessage : Maybe String
    , modal : CurrentModal
    }


init : () -> ( Model, Cmd Messages.Msg )
init _ =
    let
        graphContents =
            { graph = Graph.empty
            , items = Set.empty
            }
    in
    ( Model graphContents Search.mkModel Nothing NoModal, Cmd.none )



-- Update


updateModelForError : Model -> String -> Model
updateModelForError model err =
    { model | errorMessage = Just err }


doAddRecipe :
    Model
    -> CompleteRecipe
    -> List ItemSpec
    -> List ItemSpec
    -> ( Model, Cmd Messages.Msg )
doAddRecipe model recipe inputs outputs =
    let
        emptyNodeContext : Item -> Graph.NodeContext CraftingGraphNode CraftingGraphEdge
        emptyNodeContext item =
            Graph.NodeContext (mkItemNode item) IntDict.empty IntDict.empty

        insertWithDefault :
            List ItemSpec
            -> Graph CraftingGraphNode CraftingGraphEdge
            -> Graph CraftingGraphNode CraftingGraphEdge
        insertWithDefault vs g =
            List.foldl
                (\v og ->
                    Graph.update
                        v.item.id
                        (Maybe.withDefault (emptyNodeContext v.item) >> Just)
                        og
                )
                g
                vs

        edgeDictFromList list =
            List.map (\is -> ( is.item.id, CraftingGraphEdge 0 is.quantity )) list
                |> IntDict.fromList

        recipeNodeContext =
            Graph.NodeContext (mkRecipeNode recipe)
                (edgeDictFromList inputs)
                (edgeDictFromList outputs)

        --- Insert all the inputs into the graph as nodes, possibly unconnected
        graphWithInputNodes =
            insertWithDefault inputs model.graphContents.graph

        graphWithOutputNodes =
            insertWithDefault outputs graphWithInputNodes

        --- Make sure the recipe node is in the graph
        graphWithRecipe =
            Graph.update -recipe.recipeId
                (\context ->
                    Just <|
                        case context of
                            Nothing ->
                                recipeNodeContext

                            Just ctx ->
                                { ctx
                                    | incoming = IntDict.union ctx.incoming recipeNodeContext.incoming
                                    , outgoing = IntDict.union ctx.outgoing recipeNodeContext.outgoing
                                }
                )
                graphWithOutputNodes

        --- Update the set of items that are on the grid
        newItems : Set Int
        newItems =
            List.foldl
                (\op oldSet -> Set.insert op.item.id oldSet)
                (List.foldl
                    (\inp oldSet -> Set.insert inp.item.id oldSet)
                    model.graphContents.items
                    inputs
                )
                outputs

        newContents =
            { graph = graphWithRecipe
            , items = newItems
            }
    in
    ( { model | searchBar = Search.mkModel, modal = NoModal, graphContents = newContents }
    , Cmd.none
      -- nodeOut (graphNodeEncoder itemNode)
    )


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

            Messages.GridMsg (Messages.AddRecipeToGrid recipe inputs) ->
                doAddRecipe model recipe inputs recipe.outputs

            Messages.PopRecipeModal item ->
                update (Messages.RecipeModalMsg Messages.SendPartialRequest)
                    { model
                        | modal = RecipeModal <| RM.mkModel item
                        , searchBar = Search.mkModel
                    }

            Messages.PopRefinementModal target recipe ->
                ( { model | modal = RefinementModal <| RFM.mkModel target recipe model.graphContents.items }, Cmd.none )

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
            [ text (Graph.toString (Debug.toString >> Just) (Debug.toString >> Just) model.graphContents.graph)
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

                RefinementModal modal ->
                    [ RFM.view modal ]

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
