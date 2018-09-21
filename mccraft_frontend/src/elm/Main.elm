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
import Json.Decode as Decode exposing (Decoder)
import Json.Decode.Pipeline as Pipeline exposing (required)
import Json.Encode as Encode
import List.Extra as LE
import Random
import Regex
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


type alias PartialRecipe =
    { machineName : String
    , machineId : Int
    , recipeId : Int
    }


partialRecipeDecoder : Decoder PartialRecipe
partialRecipeDecoder =
    Decode.succeed PartialRecipe
        |> required "machine_name" Decode.string
        |> required "machine_id" Decode.int
        |> required "recipe_id" Decode.int


type alias RecipeData =
    { inputs : List (List ItemSpec)
    , outputs : List ItemSpec
    }


recipeDataDecoder : Decoder RecipeData
recipeDataDecoder =
    Decode.succeed RecipeData
        |> required "input_slots" (Decode.list (Decode.list itemSpecDecoder))
        |> required "outputs" (Decode.list itemSpecDecoder)


type alias CompleteRecipe =
    { machineName : String
    , machineId : Int
    , recipeId : Int
    , inputs : List (List ItemSpec)
    , outputs : List ItemSpec
    }


itemSlotDecoder : Decoder (List ItemSpec)
itemSlotDecoder =
    Decode.succeed (\items -> items)
        |> required "items" (Decode.list itemSpecDecoder)


completeRecipeDecoder : PartialRecipe -> Decoder CompleteRecipe
completeRecipeDecoder partial =
    Decode.succeed (\inputs outputs -> CompleteRecipe partial.machineName partial.machineId partial.recipeId inputs outputs)
        |> required "input_slots" (Decode.list itemSlotDecoder)
        |> required "outputs" (Decode.list itemSpecDecoder)


type alias ItemSpec =
    { item : Item
    , quantity : Int
    }


itemSpecDecoder : Decoder ItemSpec
itemSpecDecoder =
    Decode.succeed (\id hname mcid ty quant -> ItemSpec (Item id hname mcid ty) quant)
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


type alias RenderableItem a =
    { a
        | minecraftId : String
        , itemName : String
        , ty : ItemType
    }


itemDecoder : Decoder Item
itemDecoder =
    Decode.succeed Item
        |> required "id" Decode.int
        |> required "human_name" Decode.string
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


type alias SearchResult =
    { item : Item
    }


mkSearchResult : Item -> SearchResult
mkSearchResult i =
    SearchResult i


type alias RecipeModalInputSlot =
    { itemSpecs : Array ItemSpec
    , scale : Int
    , selected : Int
    }


type alias RecipeModalRecipe =
    { inputSlots : List RecipeModalInputSlot
    , outputs : List ItemSpec
    , parent : CompleteRecipe
    }


modalRecipeFromComplete : CompleteRecipe -> RecipeModalRecipe
modalRecipeFromComplete recipe =
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

        convertInputList (scale, slot) =
            RecipeModalInputSlot (Array.fromList slot) scale 0
    in
    RecipeModalRecipe inputs outputs parent


type alias RecipeModal =
    { targetOutput : Item
    , knownPartials : Dict Int (List PartialRecipe)
    , shownCompletes : List RecipeModalRecipe
    }


mkRecipeModal : Item -> RecipeModal
mkRecipeModal item =
    RecipeModal item Dict.empty []


type alias Model =
    { graph : Graph CraftingGraphNode GraphEdge
    , searchResults : List SearchResult
    , errorMessage : Maybe String
    , recipeModal : Maybe RecipeModal
    }


init : () -> ( Model, Cmd Msg )
init _ =
    ( Model Graph.empty [] Nothing Nothing, Cmd.none )



-- Update


type GridMsg
    = AddItem Item


type RecipeModalMsg
    = SendPartialRequest
    | ApplyPartials (List PartialRecipe)
    | SelectMachine Int
    | AddRecipe CompleteRecipe
    | CancelRecipeModal


type Msg
    = SearchItem String
    | ItemSearchResults (Result Http.Error (List Item))
    | GridMsg GridMsg
    | PopRecipeModalFor Item
    | RecipeModalMsg RecipeModalMsg
    | FlashError String


doItemSearch : String -> Model -> ( Model, Cmd Msg )
doItemSearch term model =
    if String.length term < 3 then
        ( { model | searchResults = [] }, Cmd.none )

    else
        let
            url =
                Url.relative [ "search.json" ] [ Url.string "q" term ]
        in
        ( model, Http.send ItemSearchResults (Http.get url (Decode.list itemDecoder)) )


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


updateRecipeModal : Model -> (RecipeModal -> ( RecipeModal, Cmd Msg )) -> ( Model, Cmd Msg )
updateRecipeModal model f =
    case model.recipeModal of
        Just recipeModal ->
            let
                ( newModal, cmd ) =
                    f recipeModal
            in
            ( { model | recipeModal = Just newModal }, cmd )

        Nothing ->
            ( model, Cmd.none )


doSendPartialRequest : RecipeModal -> ( RecipeModal, Cmd Msg )
doSendPartialRequest model =
    let
        processResponse machineList =
            case machineList of
                Ok list ->
                    RecipeModalMsg (ApplyPartials list)

                Err err ->
                    FlashError (handleHttpError err)

        url =
            Url.relative [ "producers", String.append (String.fromInt model.targetOutput.id) ".json" ] []
    in
    ( model, Http.send processResponse (Http.get url (Decode.list partialRecipeDecoder)) )


doApplyPartials : List PartialRecipe -> RecipeModal -> ( RecipeModal, Cmd Msg )
doApplyPartials partials model =
    let
        partialsDict =
            List.foldl
                (\x d ->
                    Dict.update
                        x.machineId
                        (\v -> Maybe.withDefault [] v |> (::) x |> Just)
                        d
                )
                Dict.empty
                partials

        firstMachine =
            List.head (Dict.keys partialsDict)

        -- Dict.fromList (List.map (\x -> (x.machineName, )) partials)
        updatedModel =
            { model | knownPartials = partialsDict }
    in
    case firstMachine of
        Just machine ->
            doSelectMachine machine updatedModel

        Nothing ->
            ( updatedModel, Cmd.none )


doSelectMachine : Int -> RecipeModal -> ( RecipeModal, Cmd Msg )
doSelectMachine machine model =
    let
        processResponse recipeResponse =
            case recipeResponse of
                Ok recipe ->
                    RecipeModalMsg (AddRecipe recipe)

                Err err ->
                    FlashError (handleHttpError err)

        partials =
            Maybe.withDefault [] <| Dict.get machine model.knownPartials

        urls =
            List.map
                (\partial ->
                    Url.relative
                        [ "recipe"
                        , String.append (String.fromInt partial.recipeId) ".json"
                        ]
                        []
                )
                partials

        requests =
            List.map (\( partial, url ) -> Http.get url (completeRecipeDecoder partial)) <| LE.zip partials urls

        commands =
            List.map (\req -> Http.send processResponse req) requests
    in
    ( { model | shownCompletes = [] }, Cmd.batch commands )


doAddRecipe : CompleteRecipe -> RecipeModal -> ( RecipeModal, Cmd Msg )
doAddRecipe recipe model =
    ( { model | shownCompletes = modalRecipeFromComplete recipe :: model.shownCompletes }, Cmd.none )


doRecipeModalMsg : RecipeModalMsg -> Model -> ( Model, Cmd Msg )
doRecipeModalMsg msg model =
    case msg of
        SelectMachine machine ->
            updateRecipeModal model <| doSelectMachine machine

        AddRecipe recipe ->
            updateRecipeModal model <| doAddRecipe recipe

        SendPartialRequest ->
            updateRecipeModal model <| doSendPartialRequest

        ApplyPartials partials ->
            updateRecipeModal model <| doApplyPartials partials

        CancelRecipeModal ->
            ( { model | recipeModal = Nothing }, Cmd.none )


updateModelForError : Model -> String -> Model
updateModelForError model err =
    { model | errorMessage = Just err }


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    Debug.log ("Processing message " ++ Debug.toString msg)
        (case msg of
            SearchItem term ->
                doItemSearch term model

            ItemSearchResults res ->
                case res of
                    Ok item ->
                        ( { model | searchResults = List.map mkSearchResult item }, Cmd.none )

                    Err item ->
                        ( updateModelForError model (handleHttpError item), Cmd.none )

            GridMsg (AddItem item) ->
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
                ( { model | searchResults = [], graph = newGraph }
                , nodeOut (graphNodeEncoder itemNode)
                )

            PopRecipeModalFor item ->
                update (RecipeModalMsg SendPartialRequest)
                    { model
                        | recipeModal = Just <| mkRecipeModal item
                        , searchResults = []
                    }

            RecipeModalMsg rmm ->
                doRecipeModalMsg rmm model

            --- TODO: display an error to the user. Build infrastructure like Flask's flashes?
            FlashError emsg ->
                ( updateModelForError model emsg, Cmd.none )
        )



-- VIEW


debugPane : Model -> Html Msg
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


urlForItem : RenderableItem a -> String
urlForItem ri =
    let
        formatMCID s =
            let
                cleanedMCID =
                    String.replace ":" "/" s
            in
            String.append cleanedMCID ".png"
    in
    case ri.ty of
        Fluid ->
            Url.relative [ "images", "fluids", String.append (String.replace ":" "_" ri.minecraftId) ".png" ] []

        ItemStack ->
            Url.relative [ "images", "items", formatMCID ri.minecraftId ] []

        UnknownType ->
            Url.relative [ "static", "ohno.png" ] []


itemIcon : List (Attribute Msg) -> RenderableItem a -> Html Msg
itemIcon extraAttrs item =
    let
        myAttrs =
            [ class "item-icon"
            , class "mc-text"
            , src (urlForItem item)
            , alt item.itemName
            ]
    in
    img (myAttrs ++ extraAttrs) [ text item.itemName ]


itemLine : List (Attribute Msg) -> Item -> Html Msg
itemLine extraAttrs item =
    div ([ class "item-line" ] ++ extraAttrs)
        [ div [ class "item-line-left" ]
            [ itemIcon [] item
            , div
                [ class "item-line-name" ]
                [ text item.itemName ]
            ]
        , div
            [ class "item-mcid" ]
            [ text item.minecraftId ]
        ]


viewRecipeModalCraftingListEntry : RecipeModal -> List PartialRecipe -> Html Msg
viewRecipeModalCraftingListEntry model recipes =
    let
        machineId =
            List.head recipes |> Maybe.map (\y -> y.machineId) |> Maybe.withDefault -1

        machineName =
            List.head recipes |> Maybe.map (\y -> y.machineName) |> Maybe.withDefault "UNKNOWN MACHINE"

        selectedMachine =
            List.head model.shownCompletes |> Maybe.map (\y -> y.parent.machineId) |> Maybe.withDefault -1

        classes =
            "modal-crafting-type"
                :: (if machineId == selectedMachine then
                        [ "selected" ]

                    else
                        []
                   )

        attrs =
            onClick (RecipeModalMsg (SelectMachine machineId)) :: List.map class classes
    in
    div attrs
        [ text machineName ]


viewItemSpec : ItemSpec -> Html Msg
viewItemSpec spec =
    div [ class "item-spec" ]
        [ itemIcon [] spec.item
        , div [ class "item-spec-nr" ] [ text (String.fromInt spec.quantity) ]
        ]


viewRecipeModalInputSlot : RecipeModalInputSlot -> Html Msg
viewRecipeModalInputSlot slot =
    Array.get slot.selected slot.itemSpecs
        |> Maybe.map (\spec -> viewItemSpec { spec | quantity = spec.quantity * slot.scale })
        |> Maybe.withDefault (text "")


viewModalRecipe : RecipeModalRecipe -> Html Msg
viewModalRecipe recipe =
    let
        inputs =
            div [ class "modal-recipe-inputs" ] (List.map viewRecipeModalInputSlot recipe.inputSlots)

        outputs =
            div [ class "modal-recipe-outputs" ] (List.map viewItemSpec recipe.outputs)
    in
    div [ class "modal-recipe" ]
        [ inputs
        , i [ class "material-icons modal-recipe-arrow" ] [ text "arrow_right_alt" ]
        , outputs
        ]


viewRecipeModal : RecipeModal -> Html Msg
viewRecipeModal modal =
    div [ class "modal" ]
        [ div [ class "modal-content" ]
            [ div [ class "modal-header" ]
                [ itemLine [] modal.targetOutput
                , i [ class "material-icons modal-close", onClick (RecipeModalMsg CancelRecipeModal) ] [ text "close" ]
                ]
            , div [ class "modal-body" ]
                [ div [ class "modal-left" ]
                    (List.map
                        (viewRecipeModalCraftingListEntry modal)
                        (Dict.values modal.knownPartials)
                    )
                , div [ class "modal-right" ]
                    [ div [ class "modal-recipe-list" ] (List.map viewModalRecipe modal.shownCompletes)
                    ]
                ]
            , div [ class "modal-footer" ]
                [ text "Output item ID: "
                , text (String.fromInt modal.targetOutput.id)
                ]
            ]
        ]


searchResult : Int -> SearchResult -> Html Msg
searchResult index result =
    itemLine
        [ class "search-result"
        , class
            (if modBy 2 index == 0 then
                "even"

             else
                "odd"
            )
        , onClick (PopRecipeModalFor result.item)
        ]
        result.item


searchBox : Model -> Html Msg
searchBox model =
    div [ class "primary-search-wrapper" ]
        [ input
            [ id "primary-search"
            , class "primary-search"
            , type_ "text"
            , placeholder "Item"
            , onInput SearchItem
            ]
            []
        , div [ class "search-results" ] (List.indexedMap searchResult model.searchResults)
        ]


view : Model -> Html Msg
view model =
    let
        recipeModal =
            case model.recipeModal of
                Just modal ->
                    [ viewRecipeModal modal ]

                Nothing ->
                    []
    in
    div []
        ([ debugPane model
         , searchBox model
         ]
            ++ recipeModal
        )



-- Subscriptions


subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.none
