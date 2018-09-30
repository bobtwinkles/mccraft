module BOMModal exposing (Model, mkModel, view)

import CraftingGraph as CG
import Debug
import Graph exposing (Graph)
import Graph.Tree as Tree
import Html exposing (Html, div)
import Html.Attributes exposing (class)
import Html.Events exposing (..)
import IntDict exposing (IntDict)
import ItemRendering exposing (itemIcon)
import Messages exposing (Msg)
import ModalRendering exposing (withModal)
import PrimaryModel exposing (Item)
import Svg exposing (..)
import Svg.Attributes exposing (transform)


type alias Model =
    { graph : Graph CG.Node CG.Edge
    , items : IntDict Item
    , initialItems : IntDict Item
    , bom : IntDict Int
    }


mkModel =
    Model


type alias LayoutSubtree =
    { self : List (Svg Msg)
    , children : LayoutSubtreeChildren
    , x : Int
    , y : Int
    , width : Int
    }


type LayoutSubtreeChildren
    = LayoutSubtreeChildren (List LayoutSubtree)


mkLayout : List (Svg Msg) -> LayoutSubtree
mkLayout self =
    { self = self, children = LayoutSubtreeChildren [], x = 0, y = 0, width = 1 }


nodeSpacing =
    60


doLayout : LayoutSubtree -> List (Svg Msg)
doLayout tree =
    let
        transform =
            String.concat
                [ "translate("
                , String.fromInt (nodeSpacing * tree.x)
                , ","
                , String.fromInt (nodeSpacing * tree.y)
                , ")"
                ]

        attrs =
            [ Svg.Attributes.class "bom-subtree"
            , Svg.Attributes.transform transform
            ]

        (LayoutSubtreeChildren children) =
            tree.children
    in
    g attrs tree.self :: List.concatMap doLayout children


layoutGraph : Graph CG.Node CG.Edge -> IntDict Item -> IntDict Int -> Svg Msg
layoutGraph graph initial bom =
    let
        renderNode : CG.Node -> List (Svg Msg)
        renderNode node =
            case node of
                CG.ItemGraphNode ign ->
                    [ g [] [ text_ [] [ text ign.item.itemName ] ] ]

                CG.RecipeGraphNode rgn ->
                    [ g [] [ text_ [] [ text rgn.machineName ] ] ]

        -- Called after the node is processed
        -- acc is the current layout subtree, with up-to-date child information
        -- but stale summary information
        finalizeNode : LayoutSubtree -> LayoutSubtree -> LayoutSubtree
        finalizeNode p acc =
            let
                (LayoutSubtreeChildren pChildren) =
                    p.children

                newChildren =
                    acc :: pChildren

                totalWidth =
                    Debug.log ("Total width of " ++ Debug.toString p) (List.foldl (.width >> (+)) 0 newChildren)
            in
            { p
                | children = LayoutSubtreeChildren newChildren
                , y = acc.y + 1
                , x = totalWidth // 2
                , width = totalWidth
            }

        -- Begins processing of a node
        -- Returns a pair of (initial self node, how to add child to self)
        processNode :
            Graph.NodeContext CG.Node CG.Edge
            -> LayoutSubtree
            -> ( LayoutSubtree, LayoutSubtree -> LayoutSubtree )
        processNode ctx parentAcc =
            ( mkLayout (renderNode ctx.node.label), finalizeNode parentAcc )

        fullContextWrapper :
            Graph.DfsNodeVisitor CG.Node CG.Edge acc
            -> Graph.NodeContext CG.Node CG.Edge
            -> acc
            -> ( acc, acc -> acc )
        fullContextWrapper f fakeContext acc =
            Graph.get fakeContext.node.id graph
                |> Maybe.map (\ctx -> f ctx acc)
                |> Maybe.withDefault ( acc, \x -> x )

        computedLayout =
            Graph.guidedDfs
                Graph.alongIncomingEdges
                (fullContextWrapper processNode)
                (IntDict.keys initial)
                (mkLayout [ text "" ])
                graph

        root =
            g [] <| doLayout <| Tuple.first computedLayout
    in
    root


view : Model -> Html Messages.Msg
view model =
    let
        header =
            [ div [ class "modal-header-text" ] [ text "Export" ] ]

        content =
            [ div [ class "bom-items" ] <| List.filterMap renderItem <| IntDict.keys model.bom
            , div [ class "bom-graph" ] [ svg [] [ layoutGraph model.graph model.initialItems model.bom ] ]
            ]

        renderItem key =
            Maybe.map2
                (\item count ->
                    div [ class "bom-item" ]
                        [ itemIcon [] item
                        , div [ class "bom-item-count" ] [ Html.text <| String.fromInt count ]
                        ]
                )
                (IntDict.get key model.items)
                (IntDict.get key model.bom)
    in
    withModal header content
