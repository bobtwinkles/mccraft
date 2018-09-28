port module Main exposing (Model, init, main)

import BOMModal as BOM
import Browser
import CraftingGraph as CG
import Debug
import Graph exposing (Edge, Graph, Node, NodeId)
import Html exposing (..)
import Html.Attributes exposing (alt, class, id, placeholder, src, type_)
import Html.Events exposing (..)
import IOModal as IOM
import IntDict
import ItemRendering exposing (itemLine, urlForItem)
import Json.Decode as Decode
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


port graphOut : Encode.Value -> Cmd msg


port itemClicked : (Int -> msg) -> Sub msg


port removeRecipe : (Int -> msg) -> Sub msg



-- Model


type CurrentModal
    = NoModal
    | RecipeModal RM.Model
    | RefinementModal RFM.Model
    | ImportModal IOM.ImportModal
    | ExportModal IOM.ExportModal
    | RemoveRecipeModal RRM.Model
    | BOMModal BOM.Model


type alias Model =
    { graphContents :
        { graph : Graph CG.Node CG.Edge
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
        emptyNodeContext : Item -> Graph.NodeContext CG.Node CG.Edge
        emptyNodeContext item =
            Graph.NodeContext (CG.mkItemNode item) IntDict.empty IntDict.empty

        insertWithDefault :
            List ItemSpec
            -> Graph CG.Node CG.Edge
            -> ( Graph CG.Node CG.Edge, List (Graph.Node CG.Node) )
        insertWithDefault vs g =
            List.foldl
                (\v ( og, on ) ->
                    ( Graph.update
                        v.item.id
                        (Maybe.withDefault (emptyNodeContext v.item) >> Just)
                        og
                    , CG.mkItemNode v.item :: on
                    )
                )
                ( g, [] )
                vs

        edgeDictFromList list =
            List.map (\is -> ( is.item.id, CG.Edge 0 is.quantity )) list
                |> IntDict.fromList

        inputEdges =
            edgeDictFromList inputs

        outputEdges =
            edgeDictFromList outputs

        recipeNode =
            CG.mkRecipeNode recipe

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
    , graphOut <| CG.graphEncoder graphWithRecipe
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
    , graphOut <| CG.graphEncoder gced
    )


serializeGraph : Graph CG.Node CG.Edge -> String
serializeGraph graph =
    Encode.encode 0 (CG.graphEncoder graph)


importFromString : String -> Result Decode.Error Model
importFromString str =
    let
        graphDecode =
            Decode.decodeString CG.graphDecoder str

        buildFromObj obj =
            let
                graph =
                    obj

                items =
                    Set.fromList
                        (List.filterMap
                            (\x ->
                                if x.id > 0 then
                                    Just x.id

                                else
                                    Nothing
                            )
                            (Graph.nodes graph)
                        )
            in
            Model { graph = graph, items = items } Search.mkModel Nothing NoModal
    in
    Result.map buildFromObj graphDecode


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

            Messages.PopBomModal item ->
                let
                    ( quants, items ) =
                        CG.graphBom model.graphContents.graph (IntDict.singleton item.id 1)
                in
                ( { model | modal = BOMModal <| BOM.mkModel items quants }, Cmd.none )

            Messages.ExitModal ->
                ( { model | modal = NoModal }, Cmd.none )

            Messages.DoImport s ->
                case importFromString s of
                    Err x ->
                        ( updateModelForError model (Decode.errorToString x), Cmd.none )

                    Ok v ->
                        ( v, graphOut <| CG.graphEncoder v.graphContents.graph )

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


viewEdgeItems : Graph CG.Node CG.Edge -> List (Html Messages.Msg)
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
                        CG.ItemGraphNode ign ->
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
        (div [ class "sidebar-heading" ] [ text "Outputs" ]
            :: List.map
                (\x -> itemLine [ onClick (Messages.PopBomModal x) ] x)
                outputItems
        )
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

                BOMModal bom ->
                    [ BOM.view bom ]

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
                                CG.ItemGraphNode ign ->
                                    Just ign.item

                                _ ->
                                    Nothing
                        )
                    |> Maybe.map Messages.PopRecipeModal
                    |> Maybe.withDefault Messages.ExitModal
            )
        , removeRecipe Messages.PopRemoveRecipeModal
        ]
