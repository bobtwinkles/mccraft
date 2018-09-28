module CraftingGraph exposing
    ( Edge
    , Node(..)
    , graphBom
    , graphDecoder
    , graphEncoder
    , mkItemNode
    , mkRecipeNode
    )

import Debug
import Graph exposing (Graph)
import IntDict exposing (IntDict)
import ItemRendering exposing (urlForItem)
import Json.Decode as Decode
import Json.Decode.Pipeline exposing (required)
import Json.Encode as Encode
import PrimaryModel exposing (CompleteRecipe, Item, ItemSpec, ItemType(..))



--- Types


type alias ItemNode =
    { item : Item }


type alias RecipeNode =
    { machineName : String }


{-| A node in the crafting graph
-}
type Node
    = ItemGraphNode ItemNode
    | RecipeGraphNode RecipeNode


mkItemNode : Item -> Graph.Node Node
mkItemNode item =
    Graph.Node item.id (ItemGraphNode <| ItemNode item)


mkRecipeNode : CompleteRecipe -> Graph.Node Node
mkRecipeNode recipe =
    Graph.Node -recipe.recipeId (RecipeGraphNode <| RecipeNode recipe.machineName)


{-| An edge in the crafting graph
-}
type alias Edge =
    -- Identifier for this edge
    { id : Int

    -- How much "to" is produced from each "from"
    , production : Int
    }



-- Graph serialization stuff


graphEdgeEncoder : Graph.Edge Edge -> Encode.Value
graphEdgeEncoder edge =
    Encode.object
        [ ( "source", Encode.int edge.from )
        , ( "target", Encode.int edge.to )
        , ( "production", Encode.int edge.label.production )
        ]


graphEdgeDecoder : Decode.Decoder (Graph.Edge Edge)
graphEdgeDecoder =
    Decode.succeed (\s t p -> Graph.Edge s t (Edge 0 p))
        |> required "source" Decode.int
        |> required "target" Decode.int
        |> required "production" Decode.int


graphNodeEncoder : Graph.Node Node -> Encode.Value
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


graphNodeDecoder : Decode.Decoder (Graph.Node Node)
graphNodeDecoder =
    let
        itemStruct : Int -> String -> String -> PrimaryModel.ItemType -> Graph.Node Node
        itemStruct id name mcid cls =
            mkItemNode <| { id = id, itemName = name, minecraftId = mcid, ty = cls }

        recipeStruct : Int -> String -> Graph.Node Node
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


graphEncoder : Graph Node Edge -> Encode.Value
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


graphDecoder : Decode.Decoder (Graph Node Edge)
graphDecoder =
    let
        buildFromObj edges nodes =
            Graph.fromNodesAndEdges nodes edges
    in
    Decode.succeed buildFromObj
        |> required "edges" (Decode.list graphEdgeDecoder)
        |> required "nodes" (Decode.list graphNodeDecoder)



-- BOM generation


{-| Generate a BOM. The output is a map of item ID to quantity and item ID to
item object. The input is the graph to use as a source, and a dictionary of
(item ID -> requested quantity).
-}
graphBom : Graph Node Edge -> IntDict Int -> ( IntDict Int, IntDict Item )
graphBom graph initial =
    let
        -- We want to compute how many of whatever this node is would be
        -- required to complete the craft. For item nodes, this means the
        -- amount of crafts for the recipes they feed into multiplied by the
        -- "production" along that edge (i.e. how much each of the item that
        -- recipe requires). For recipe nodes, this means maximum of the
        -- ceiling-division of (output_i / production_i). That is, how many
        -- times does this recipe need to run to produce at least the minimum
        -- required amount of each output.
        quantityRequiredFor : Graph.NodeContext Node Edge -> IntDict Int -> IntDict Int
        quantityRequiredFor context requiredCounts =
            case context.node.label of
                ItemGraphNode ign ->
                    -- Sum over the supply needed to each of the upstream edges
                    let
                        requiredCount =
                            IntDict.foldl
                                (\upstreamNodeId upstreamEdge ov ->
                                    let
                                        upstreamOps =
                                            IntDict.get upstreamNodeId requiredCounts |> Maybe.withDefault 0
                                    in
                                    ov + (upstreamOps * upstreamEdge.production)
                                )
                                0
                                context.outgoing

                        updateFunc =
                            Maybe.withDefault 0 >> (+) requiredCount >> Just
                    in
                    IntDict.update context.node.id updateFunc requiredCounts

                RecipeGraphNode rgn ->
                    -- Find the maximum number of ops required by any of upstream outputs
                    let
                        requiredCount =
                            Debug.log "recipe upstream computed"
                                (IntDict.foldl
                                    (\upstreamNodeId upstreamEdge ov ->
                                        let
                                            upstreamOps =
                                                Debug.log "recipe upstream" (IntDict.get upstreamNodeId requiredCounts |> Maybe.withDefault 0)
                                        in
                                        max ov <| ((upstreamOps + upstreamEdge.production - 1) // upstreamEdge.production)
                                    )
                                    0
                                    (Debug.log "recipe outgoing" context.outgoing)
                                )

                        updateFunc =
                            Maybe.withDefault 0 >> max requiredCount >> Just
                    in
                    IntDict.update context.node.id updateFunc requiredCounts

        fullContextWrapper : (Graph.NodeContext Node Edge -> acc -> acc) -> Graph.NodeContext Node Edge -> acc -> acc
        fullContextWrapper f fakeContext acc =
            Graph.get fakeContext.node.id graph
                |> Maybe.map (\ctx -> f ctx acc)
                |> Maybe.withDefault acc

        ( quants, g ) =
            Graph.guidedBfs
                Graph.alongIncomingEdges
                (Graph.ignorePath <| fullContextWrapper quantityRequiredFor)
                (IntDict.keys initial)
                initial
                graph

        itemMap =
            Graph.fold
                (\ctx om ->
                    case ctx.node.label of
                        ItemGraphNode ign ->
                            IntDict.insert ctx.node.id ign.item om

                        _ ->
                            om
                )
                IntDict.empty
                graph
    in
    ( quants, itemMap )
