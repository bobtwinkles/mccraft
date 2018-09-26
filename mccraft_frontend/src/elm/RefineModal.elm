module RefineModal exposing (Model, mkModel, update, view)

import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import ItemRendering exposing (itemIcon, itemLine)
import Messages exposing (RefineModalMsg)
import PrimaryModel exposing (DedupedRecipe, InputSlot, Item, ItemSpec)
import Set exposing (Set)



-- Types


type alias InputSlotStack =
    { selected : Maybe ItemSpec
    , scale : Int
    , availableInGrid : List ItemSpec
    , alternatives : List ItemSpec
    }


type alias Model =
    { targetOutput : Item
    , parent : DedupedRecipe
    , inputSlots : List InputSlotStack
    }



-- Initialization functions


mkModel : Item -> DedupedRecipe -> Set Int -> Model
mkModel targetOutput recipe gridItemIds =
    let
        inputSlots =
            List.map convertInputSlot recipe.inputSlots

        convertInputSlot slot =
            let
                ( availableInGrid, alternatives ) =
                    List.foldl
                        (\is ( avail, alt ) ->
                            if Set.member is.item.id gridItemIds then
                                ( is :: avail, alt )

                            else
                                ( avail, is :: alt )
                        )
                        ( [], [] )
                        slot.itemSpecs
            in
            case availableInGrid of
                inGrid :: rest ->
                    InputSlotStack (Just inGrid) slot.scale rest alternatives

                [] ->
                    case alternatives of
                        alt :: rest ->
                            InputSlotStack (Just alt) slot.scale [] rest

                        [] ->
                            InputSlotStack Nothing slot.scale [] []
    in
    Model targetOutput recipe inputSlots



-- Update functions


update : RefineModalMsg -> Model -> ( Model, Cmd Messages.Msg )
update msg model =
    case msg of
        Messages.SelectItem slotId newIndex ->
            ( model, Cmd.none )



-- View functions


createAddMsg : Model -> Messages.GridMsg
createAddMsg model =
    let
        inputs =
            List.filterMap
                (\x ->
                    x.selected
                        |> Maybe.map
                            -- We need to adjust the quantity to incorporate the
                            -- scale of the stack
                            (\v -> { v | quantity = v.quantity * x.scale })
                )
                model.inputSlots
    in
    Messages.AddRecipeToGrid model.parent.parent inputs


viewItemSpec : String -> ItemSpec -> Html Messages.Msg
viewItemSpec clazz is =
    div
        [ class "refinement-item-spec"
        , class clazz
        ]
        [ itemIcon [] is.item
        , div [] [ text (String.fromInt is.quantity) ]
        ]


viewInputSlot : InputSlotStack -> Html Messages.Msg
viewInputSlot is =
    let
        selectedSpec =
            Maybe.map (\x -> [ viewItemSpec "selected" x ]) is.selected
                |> Maybe.withDefault []

        inGridItems =
            List.map (viewItemSpec "in-grid") is.availableInGrid

        alternatives =
            List.map (viewItemSpec "alts") is.alternatives
    in
    div [ class "refinement-input-slot" ]
        ([ div [ class "refinement-input-slot-scale" ]
            [ text (String.fromInt is.scale) ]
         ]
            ++ selectedSpec
            ++ inGridItems
            ++ alternatives
        )


view : Model -> Html Messages.Msg
view model =
    div [ class "modal" ]
        [ div [ class "modal-content" ]
            [ div [ class "modal-header" ]
                [ itemLine [] model.targetOutput
                , i [ class "material-icons modal-close", onClick Messages.ExitModal ] [ text "close" ]
                ]
            , div [ class "refinement-recipe" ]
                [ div [ class "refinement-inputs" ] (List.map viewInputSlot model.inputSlots)
                , i [ class "material-icons modal-recipe-arrow" ] [ text "arrow_right_alt" ]
                , div [ class "refinement-outputs" ] (List.map (viewItemSpec "output") model.parent.outputs)
                ]
            , div
                [ class "refinement-accept-button"
                , onClick (Messages.GridMsg (createAddMsg model))
                ]
                [ text "Accept" ]
            ]
        ]
