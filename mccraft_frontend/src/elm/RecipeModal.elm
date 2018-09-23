module RecipeModal exposing
    ( Model
    , mkModel
    , update
    , view
    )

--- Model

import Array exposing (Array)
import Dict exposing (Dict)
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import Http
import ItemRendering exposing (itemIcon, itemLine)
import Json.Decode as Decode
import List.Extra as LE
import Messages exposing (Msg, RecipeModalMsg)
import PrimaryModel exposing (..)
import Url.Builder as UB



-- TYPES


type alias InputSlot =
    { itemSpecs : List ItemSpec
    , scale : Int
    , selected : Int
    }


type alias Recipe =
    { inputSlots : List InputSlot
    , outputs : List ItemSpec
    , parent : CompleteRecipe
    }


type alias Model =
    { targetOutput : Item
    , knownPartials : Dict Int (List PartialRecipe)
    , shownCompletes : List Recipe
    }



-- Constructors


mkRecipeFromComplete : CompleteRecipe -> Recipe
mkRecipeFromComplete recipe =
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
    Recipe inputs outputs parent


mkModel : Item -> Model
mkModel item =
    Model item Dict.empty []



--- Update


doSendPartialRequest : Model -> ( Model, Cmd Msg )
doSendPartialRequest model =
    let
        processResponse machineList =
            case machineList of
                Ok list ->
                    Messages.RecipeModalMsg (Messages.ApplyPartials list)

                Err err ->
                    Messages.FlashError (handleHttpError err)

        url =
            UB.relative [ "producers", String.append (String.fromInt model.targetOutput.id) ".json" ] []
    in
    ( model, Http.send processResponse (Http.get url (Decode.list partialRecipeDecoder)) )


doApplyPartials : List PartialRecipe -> Model -> ( Model, Cmd Msg )
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


doSelectMachine : Int -> Model -> ( Model, Cmd Msg )
doSelectMachine machine model =
    let
        processResponse recipeResponse =
            case recipeResponse of
                Ok recipe ->
                    Messages.RecipeModalMsg (Messages.AddRecipe recipe)

                Err err ->
                    Messages.FlashError (handleHttpError err)

        partials =
            Maybe.withDefault [] <| Dict.get machine model.knownPartials

        urls =
            List.map
                (\partial ->
                    UB.relative
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


doAddRecipe : CompleteRecipe -> Model -> ( Model, Cmd Msg )
doAddRecipe recipe model =
    ( { model | shownCompletes = mkRecipeFromComplete recipe :: model.shownCompletes }, Cmd.none )


update : RecipeModalMsg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        Messages.SelectMachine machine ->
            doSelectMachine machine model

        Messages.AddRecipe recipe ->
            doAddRecipe recipe model

        Messages.SendPartialRequest ->
            doSendPartialRequest model

        Messages.ApplyPartials partials ->
            doApplyPartials partials model



--- View


viewRecipeModalCraftingListEntry : Model -> List PartialRecipe -> Html Msg
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
            onClick (Messages.RecipeModalMsg (Messages.SelectMachine machineId)) :: List.map class classes
    in
    div attrs
        [ text machineName ]


viewItemSpec : ItemSpec -> Html Msg
viewItemSpec spec =
    div [ class "item-spec" ]
        [ itemIcon [] spec.item
        , div [ class "item-spec-nr" ] [ text (String.fromInt spec.quantity) ]
        ]


viewRecipeModalInputSlot : InputSlot -> Html Msg
viewRecipeModalInputSlot slot =
    LE.getAt slot.selected slot.itemSpecs
        |> Maybe.map (\spec -> viewItemSpec { spec | quantity = spec.quantity * slot.scale })
        |> Maybe.withDefault (text "")


viewModalRecipe : Recipe -> Html Msg
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


view : Model -> Html Msg
view model =
    div [ class "modal" ]
        [ div [ class "modal-content" ]
            [ div [ class "modal-header" ]
                [ itemLine [] model.targetOutput
                , i [ class "material-icons modal-close", onClick Messages.CancelRecipeModal ] [ text "close" ]
                ]
            , div [ class "modal-body" ]
                [ div [ class "modal-left" ]
                    (List.map
                        (viewRecipeModalCraftingListEntry model)
                        (Dict.values model.knownPartials)
                    )
                , div [ class "modal-right" ]
                    [ div [ class "modal-recipe-list" ] (List.map viewModalRecipe model.shownCompletes)
                    ]
                ]
            , div [ class "modal-footer" ]
                [ text "Output item ID: "
                , text (String.fromInt model.targetOutput.id)
                ]
            ]
        ]
