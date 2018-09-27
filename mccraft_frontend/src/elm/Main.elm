port module Main exposing (Model, init, main)

import Browser
import Debug
import Graph exposing (Edge, Graph, Node, NodeId)
import Html exposing (..)
import Html.Attributes exposing (alt, class, id, placeholder, src, type_)
import Html.Events exposing (..)
import IOModal as IOM
import IntDict
import ItemRendering exposing (itemLine, urlForItem)
import Json.Decode as Decode
import Json.Decode.Pipeline exposing (required)
import Json.Encode as Encode
import Messages
import PrimaryModel exposing (..)
import RecipeModal as RM
import RefineModal as RFM
import Regex
import RemoveRecipeModal as RRM
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


graphEdgeEncoder : Graph.Edge CraftingGraphEdge -> Encode.Value
graphEdgeEncoder edge =
    Encode.object
        [ ( "source", Encode.int edge.from )
        , ( "target", Encode.int edge.to )
        , ( "production", Encode.int edge.label.production )
        ]


graphEdgeDecoder : Decode.Decoder (Graph.Edge CraftingGraphEdge)
graphEdgeDecoder =
    Decode.succeed (\s t p -> Graph.Edge s t (CraftingGraphEdge 0 p))
        |> required "source" Decode.int
        |> required "target" Decode.int
        |> required "production" Decode.int


graphNodeEncoder : Graph.Node CraftingGraphNode -> Encode.Value
graphNodeEncoder ent =
    case ent.label of
        ItemGraphNode ign ->
            let
                itemClass =
                    case ign.item.ty of
                        ItemStack ->
                            "Item"

                        Fluid ->
                            "Fluid"
            in
            Encode.object
                [ ( "id", Encode.int ent.id )
                , ( "ty", Encode.string "Item" )
                , ( "name", Encode.string ign.item.itemName )
                , ( "mcid", Encode.string ign.item.minecraftId )
                , ( "itemClass", Encode.string itemClass )
                , ( "imgUrl", Encode.string (urlForItem ign.item) )
                ]

        RecipeGraphNode rgn ->
            Encode.object
                [ ( "id", Encode.int ent.id )
                , ( "ty", Encode.string "Recipe" )
                , ( "machineName", Encode.string rgn.machineName )
                ]


graphNodeDecoder : Decode.Decoder (Graph.Node CraftingGraphNode)
graphNodeDecoder =
    let
        itemStruct : Int -> String -> String -> PrimaryModel.ItemType -> Graph.Node CraftingGraphNode
        itemStruct id name mcid cls =
            mkItemNode <| { id = id, itemName = name, minecraftId = mcid, ty = cls }

        recipeStruct : Int -> String -> Graph.Node CraftingGraphNode
        recipeStruct id machineName =
            Graph.Node id (RecipeGraphNode <| RecipeNode machineName)
    in
    Decode.field "ty" Decode.string
        |> Decode.andThen
            (\ty ->
                case ty of
                    "Item" ->
                        Decode.succeed itemStruct
                            |> required "id" Decode.int
                            |> required "name" Decode.string
                            |> required "mcid" Decode.string
                            |> required "itemClass" PrimaryModel.itemTypeDecoder

                    "Recipe" ->
                        Decode.succeed recipeStruct
                            |> required "id" Decode.int
                            |> required "machineName" Decode.string

                    _ ->
                        Decode.fail <| "Unsupported item type " ++ ty
            )


graphEncoder : Graph CraftingGraphNode CraftingGraphEdge -> Encode.Value
graphEncoder graph =
    let
        nodes =
            List.map graphNodeEncoder (Graph.nodes graph)

        edges =
            List.map graphEdgeEncoder (Graph.edges graph)
    in
    Encode.object
        [ ( "nodes", Encode.list (\x -> x) nodes )
        , ( "edges", Encode.list (\x -> x) edges )
        ]


port graphOut : Encode.Value -> Cmd msg


port itemClicked : (Int -> msg) -> Sub msg


port removeRecipe : (Int -> msg) -> Sub msg



-- Model


type alias ItemNode =
    { item : Item }


type alias RecipeNode =
    { machineName : String }


type CraftingGraphNode
    = ItemGraphNode ItemNode
    | RecipeGraphNode RecipeNode


mkItemNode : Item -> Graph.Node CraftingGraphNode
mkItemNode item =
    Graph.Node item.id (ItemGraphNode <| ItemNode item)


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
    | ImportModal IOM.ImportModal
    | ExportModal IOM.ExportModal
    | RemoveRecipeModal RRM.Model


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
            -> ( Graph CraftingGraphNode CraftingGraphEdge, List (Graph.Node CraftingGraphNode) )
        insertWithDefault vs g =
            List.foldl
                (\v ( og, on ) ->
                    ( Graph.update
                        v.item.id
                        (Maybe.withDefault (emptyNodeContext v.item) >> Just)
                        og
                    , mkItemNode v.item :: on
                    )
                )
                ( g, [] )
                vs

        edgeDictFromList list =
            List.map (\is -> ( is.item.id, CraftingGraphEdge 0 is.quantity )) list
                |> IntDict.fromList

        inputEdges =
            edgeDictFromList inputs

        outputEdges =
            edgeDictFromList outputs

        recipeNode =
            mkRecipeNode recipe

        recipeNodeContext =
            Graph.NodeContext recipeNode inputEdges outputEdges

        --- Insert all the inputs into the graph as nodes, possibly unconnected
        ( graphWithInputNodes, inputNodes ) =
            insertWithDefault inputs model.graphContents.graph

        ( graphWithOutputNodes, outputNodes ) =
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
    , graphOut <| graphEncoder graphWithRecipe
    )


doRemoveRecipe : Int -> Model -> ( Model, Cmd Messages.Msg )
doRemoveRecipe recipe model =
    let
        noRecipe =
            Graph.remove recipe model.graphContents.graph

        gced =
            List.foldl
                (\nid ->
                    Graph.update nid
                        (\context ->
                            case context of
                                Just ctx ->
                                    if (IntDict.size ctx.incoming + IntDict.size ctx.outgoing) == 0 then
                                        Nothing

                                    else
                                        Just ctx

                                Nothing ->
                                    Nothing
                        )
                )
                noRecipe
                (Graph.nodeIds noRecipe)

        oldContents =
            model.graphContents
    in
    ( { model | modal = NoModal, graphContents = { oldContents | graph = gced } }
    , graphOut <| graphEncoder gced
    )


serializeGraph : Graph CraftingGraphNode CraftingGraphEdge -> String
serializeGraph graph =
    Encode.encode 0
        (Encode.object
            [ ( "edges", Encode.list graphEdgeEncoder (Graph.edges graph) )
            , ( "nodes", Encode.list graphNodeEncoder (Graph.nodes graph) )
            ]
        )


importFromString : String -> Result Decode.Error Model
importFromString str =
    let
        objDecoder =
            Decode.succeed (\edges nodes -> { edges = edges, nodes = nodes })
                |> required "edges" (Decode.list graphEdgeDecoder)
                |> required "nodes" (Decode.list graphNodeDecoder)

        decoded =
            Decode.decodeString objDecoder str

        buildFromObj obj =
            let
                graph =
                    Graph.fromNodesAndEdges obj.nodes obj.edges

                items =
                    Set.fromList
                        (List.filterMap
                            (\x ->
                                if x.id > 0 then
                                    Just x.id

                                else
                                    Nothing
                            )
                            obj.nodes
                        )
            in
            Model { graph = graph, items = items } Search.mkModel Nothing NoModal
    in
    Result.map buildFromObj decoded


doModalUpdate : a -> (a -> CurrentModal) -> (a -> ( a, Cmd Messages.Msg )) -> Model -> ( Model, Cmd Messages.Msg )
doModalUpdate modal wrapModal updateModal model =
    let
        ( newModal, cmd ) =
            updateModal modal
    in
    ( { model | modal = wrapModal newModal }, cmd )


doGridMsg : Messages.GridMsg -> Model -> ( Model, Cmd Messages.Msg )
doGridMsg msg model =
    case msg of
        Messages.AddRecipeToGrid recipe inputs ->
            doAddRecipe model recipe inputs recipe.outputs

        Messages.RemoveRecipeFromGrid rid ->
            doRemoveRecipe rid model


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

            Messages.GridMsg gm ->
                doGridMsg gm model

            Messages.PopRecipeModal item ->
                update (Messages.RecipeModalMsg Messages.SendPartialRequest)
                    { model
                        | modal = RecipeModal <| RM.mkModel item
                        , searchBar = Search.mkModel
                    }

            Messages.RecipeModalMsg rmm ->
                case model.modal of
                    RecipeModal modal ->
                        doModalUpdate modal RecipeModal (RM.update rmm) model

                    _ ->
                        ( model, Cmd.none )

            Messages.PopRefinementModal target recipe ->
                ( { model | modal = RefinementModal <| RFM.mkModel target recipe model.graphContents.items }, Cmd.none )

            Messages.RefineModalMsg rmm ->
                case model.modal of
                    RefinementModal modal ->
                        doModalUpdate modal RefinementModal (RFM.update rmm) model

                    _ ->
                        ( model, Cmd.none )

            Messages.PopImportModal ->
                ( { model | modal = ImportModal IOM.mkImport }, Cmd.none )

            Messages.ImportModalMsg imm ->
                case model.modal of
                    ImportModal modal ->
                        doModalUpdate modal ImportModal (IOM.updateImport imm) model

                    _ ->
                        ( model, Cmd.none )

            Messages.PopExportModal ->
                ( { model
                    | modal =
                        ExportModal
                            (IOM.mkExport
                                (serializeGraph model.graphContents.graph)
                            )
                  }
                , Cmd.none
                )

            Messages.PopRemoveRecipeModal x ->
                ( { model | modal = RemoveRecipeModal (RRM.mkModel x) }, Cmd.none )

            Messages.ExitModal ->
                ( { model | modal = NoModal }, Cmd.none )

            Messages.DoImport s ->
                case importFromString s of
                    Err x ->
                        ( updateModelForError model (Decode.errorToString x), Cmd.none )

                    Ok v ->
                        ( v, graphOut <| graphEncoder v.graphContents.graph )

            --- TODO: display an error to the user. Build infrastructure like Flask's flashes?
            Messages.FlashError emsg ->
                ( updateModelForError model emsg, Cmd.none )
        )



-- VIEW


debugPane : Model -> Html Messages.Msg
debugPane model =
    let
        baseContent =
            [-- text (Graph.toString (Debug.toString >> Just) (Debug.toString >> Just) model.graphContents.graph)
            ]

        errorContent =
            case model.errorMessage of
                Nothing ->
                    []

                Just msg ->
                    [ br [] [], code [] [ text msg ] ]
    in
    div [ class "debug-pane" ] (baseContent ++ errorContent)


viewEdgeItems : Graph CraftingGraphNode CraftingGraphEdge -> List (Html Messages.Msg)
viewEdgeItems graph =
    let
        ( inputs, outputs ) =
            Graph.fold
                (\ctx ( inp, outp ) ->
                    if IntDict.size ctx.incoming == 0 then
                        ( ctx.node.label :: inp, outp )

                    else if IntDict.size ctx.outgoing == 0 then
                        ( inp, ctx.node.label :: outp )

                    else
                        ( inp, outp )
                )
                ( [], [] )
                graph

        itemsOnly =
            List.filterMap
                (\x ->
                    case x of
                        ItemGraphNode ign ->
                            Just ign.item

                        _ ->
                            Nothing
                )

        inputItems =
            itemsOnly inputs

        outputItems =
            itemsOnly outputs
    in
    [ div [ class "sidebar-inputs" ]
        (div [ class "sidebar-heading" ] [ text "Inputs" ]
            :: List.map (\x -> itemLine [ onClick (Messages.PopRecipeModal x) ] x) inputItems
        )
    , div [ class "sidebar-outputs" ]
        (div [ class "sidebar-heading" ] [ text "Outputs" ] :: List.map (itemLine []) outputItems)
    ]


view : Model -> Html Messages.Msg
view model =
    let
        modalView =
            case model.modal of
                RecipeModal modal ->
                    [ RM.view modal ]

                RefinementModal modal ->
                    [ RFM.view modal ]

                ImportModal im ->
                    [ IOM.viewImport im ]

                ExportModal em ->
                    [ IOM.viewExport em ]

                RemoveRecipeModal rrm ->
                    [ RRM.view rrm ]

                NoModal ->
                    []

        saveLoadButtons =
            [ div [ class "import-graph-button button", onClick Messages.PopImportModal ] [ text "Import" ]
            , div [ class "export-graph-button button", onClick Messages.PopExportModal ] [ text "Export" ]
            ]
    in
    div [ id "main" ]
        ([ debugPane model
         , Search.view model.searchBar
         ]
            ++ viewEdgeItems model.graphContents.graph
            ++ saveLoadButtons
            ++ modalView
        )



-- Subscriptions


subscriptions : Model -> Sub Messages.Msg
subscriptions model =
    Sub.batch
        [ itemClicked
            (\iid ->
                Graph.get iid model.graphContents.graph
                    |> Maybe.andThen
                        (\ctx ->
                            case ctx.node.label of
                                ItemGraphNode ign ->
                                    Just ign.item

                                _ ->
                                    Nothing
                        )
                    |> Maybe.map Messages.PopRecipeModal
                    |> Maybe.withDefault Messages.ExitModal
            )
        , removeRecipe Messages.PopRemoveRecipeModal
        ]
