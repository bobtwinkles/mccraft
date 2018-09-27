module PrimaryModel exposing
    ( CompleteRecipe
    , DedupedRecipe
    , InputSlot
    , Item
    , ItemSpec
    , ItemType(..)
    , PartialRecipe
    , completeRecipeDecoder
    , deduplicateSlots
    , handleHttpError
    , itemDecoder
    , partialRecipeDecoder
    , itemTypeDecoder
    )

import Html exposing (..)
import Html.Attributes exposing (alt, class, src)
import Http
import Json.Decode as Decode exposing (Decoder)
import Json.Decode.Pipeline as Pipeline exposing (required)
import List.Extra as LE



-- Communication structures


{-| Enumeration representing what type of item it is
-}
type ItemType
    = ItemStack
    | Fluid


{-| The part of a recipe that we get back initially. It only includes what
machine it's for and a handle for retrieving the rest of the data. Combine with
a RecipeData to get a CompleteRecipei
-}
type alias PartialRecipe =
    { machineName : String
    , machineId : Int
    , recipeId : Int
    }


{-| The data that comes back when we ask the server to complete a recipe.
Combined with a PartialRecipe, this forms a CompleteRecipe
-}
type alias RecipeData =
    { inputs : List (List ItemSpec)
    , outputs : List ItemSpec
    }


{-| Everything the system knows about a recipe, including its inputs and
outputs. The inputs is a list of "slots", with a list of the items allowed for
any given slot
-}
type alias CompleteRecipe =
    { machineName : String
    , machineId : Int
    , recipeId : Int
    , inputs : List (List ItemSpec)
    , outputs : List ItemSpec
    }


{-| Represents an individual input slot, for use after all the slots have been de-duplicated
-}
type alias InputSlot =
    { itemSpecs : List ItemSpec
    , scale : Int
    , selected : Int
    }


{-| The primary recipe type for use after deduplication
-}
type alias DedupedRecipe =
    { inputSlots : List InputSlot
    , outputs : List ItemSpec
    , parent : CompleteRecipe
    }


{-| An item in the system. The id is the internal ID, not a minecraft block/item
ID. The minecraftId string is something of the form modname:itemname, while
itemName is something human readable.
-}
type alias Item =
    { id : Int
    , itemName : String
    , minecraftId : String
    , ty : ItemType
    }


{-| A (Item, quantity) tuple basically.
-}
type alias ItemSpec =
    { item : Item
    , quantity : Int
    }



-- Decoders


{-| A decoder for partial recipes.
-}
partialRecipeDecoder : Decoder PartialRecipe
partialRecipeDecoder =
    Decode.succeed PartialRecipe
        |> required "machine_name" Decode.string
        |> required "machine_id" Decode.int
        |> required "recipe_id" Decode.int


{-| A decoder for recipe completion data
-}
recipeDataDecoder : Decoder RecipeData
recipeDataDecoder =
    Decode.succeed RecipeData
        |> required "input_slots" (Decode.list (Decode.list itemSpecDecoder))
        |> required "outputs" (Decode.list itemSpecDecoder)


{-| A decoder for recipe completion data that automatically combines it with the
partial recipe it's associated with
-}
completeRecipeDecoder : PartialRecipe -> Decoder CompleteRecipe
completeRecipeDecoder partial =
    Decode.succeed
        (\inputs outputs ->
            CompleteRecipe partial.machineName
                partial.machineId
                partial.recipeId
                inputs
                outputs
        )
        |> required "input_slots" (Decode.list itemSlotDecoder)
        |> required "outputs" (Decode.list itemSpecDecoder)


{-| Decoder for items
-}
itemDecoder : Decoder Item
itemDecoder =
    Decode.succeed Item
        |> required "id" Decode.int
        |> required "human_name" Decode.string
        |> required "minecraft_id" Decode.string
        |> required "ty" itemTypeDecoder


{-| Decodes an ItemSpec
-}
itemSpecDecoder : Decoder ItemSpec
itemSpecDecoder =
    Decode.succeed (\id hname mcid ty quant -> ItemSpec (Item id hname mcid ty) quant)
        |> required "item_id" Decode.int
        |> required "item_name" Decode.string
        |> required "minecraft_id" Decode.string
        |> required "ty" itemTypeDecoder
        |> required "quantity" Decode.int


{-| Decodes an individual item slot
-}
itemSlotDecoder : Decoder (List ItemSpec)
itemSlotDecoder =
    Decode.succeed (\items -> items)
        |> required "items" (Decode.list itemSpecDecoder)


{-| Converts a string representation of an item type into something a little
more typed
-}
matchItemType : String -> Decoder ItemType
matchItemType x =
    case x of
        "Item" ->
            Decode.succeed ItemStack

        "Fluid" ->
            Decode.succeed Fluid
        _ -> Decode.fail <| "Unknown item type " ++ x


{-| A decoder for item type fields
-}
itemTypeDecoder : Decoder ItemType
itemTypeDecoder =
    Pipeline.resolve (Decode.map matchItemType Decode.string)


{-| Convert an HTTP error into a string that makes sense to flash as an error
message
-}
handleHttpError : Http.Error -> String
handleHttpError e =
    case e of
        Http.BadPayload errMsg _ ->
            errMsg

        Http.BadUrl errMsg ->
            errMsg

        Http.Timeout ->
            "Network timeout while searching for items"

        Http.NetworkError ->
            "Network error while searching for items"

        Http.BadStatus resp ->
            "Bad status code"



-- Constructors


deduplicateSlots : CompleteRecipe -> DedupedRecipe
deduplicateSlots recipe =
    let
        inputs =
            List.map convertInputList deduplicatedSlotList

        outputs =
            recipe.outputs

        parent =
            recipe

        -- Deduplicate the slot list. This works by first sorting the items
        -- within the input list on the basis of their ID, sorting the list of
        -- slots by the ID of their items, and then grouping identical slots
        -- together
        deduplicatedSlotList =
            List.map (\( x, y ) -> ( 1 + List.length y, x )) <|
                LE.group (List.sortWith itemIDCmp (List.map (List.sortBy (\x -> x.item.id)) recipe.inputs))

        itemIDCmp a b =
            case ( a, b ) of
                ( ai :: ar, bi :: br ) ->
                    case compare ai.item.id bi.item.id of
                        LT ->
                            LT

                        GT ->
                            GT

                        EQ ->
                            itemIDCmp ar br

                ( ai, [] ) ->
                    case ai of
                        [] ->
                            EQ

                        _ ->
                            GT

                ( [], bi ) ->
                    case bi of
                        [] ->
                            EQ

                        _ ->
                            LT

        convertInputList ( scale, slot ) =
            InputSlot slot scale 0
    in
    DedupedRecipe inputs outputs parent
