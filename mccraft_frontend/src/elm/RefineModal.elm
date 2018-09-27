module RefineModal exposing (Model, mkModel, update, view)

import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import ItemRendering exposing (itemIcon, itemLine)
import List.Extra as LE
import Messages exposing (RefineModalMsg)
import ModalRendering exposing (withModal)
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
                    InputSlotStack (Just inGrid) slot.scale availableInGrid alternatives

                [] ->
                    case alternatives of
                        alt :: rest ->
                            InputSlotStack (Just alt) slot.scale [] alternatives

                        [] ->
                            InputSlotStack Nothing slot.scale [] []
    in
    Model targetOutput recipe inputSlots



-- Update functions


update : RefineModalMsg -> Model -> ( Model, Cmd Messages.Msg )
update msg model =
    case msg of
        Messages.RefineToItem slotId newItem ->
            let
                newSlots =
                    LE.updateAt slotId (\stk -> { stk | selected = Just newItem }) model.inputSlots
            in
            ( { model | inputSlots = newSlots }, Cmd.none )



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


viewItemSpec : List (Attribute Messages.Msg) -> ItemSpec -> Html Messages.Msg
viewItemSpec extraAttrs is =
    div
        (class "refinement-item-spec" :: extraAttrs)
        [ itemIcon [] is.item
        , div [] [ text (String.fromInt is.quantity) ]
        ]


viewInputSlot : Int -> InputSlotStack -> Html Messages.Msg
viewInputSlot idx is =
    let
        selectableSpec clazz stk =
            viewItemSpec [ class clazz, onClick (Messages.RefineModalMsg (Messages.RefineToItem idx stk)) ] stk

        selectedSpec =
            Maybe.map (\x -> [ viewItemSpec [ class "selected" ] x ]) is.selected
                |> Maybe.withDefault []

        inGridItems =
            List.map (selectableSpec "in-grid") is.availableInGrid

        alternatives =
            List.map (selectableSpec "alt") is.alternatives
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
    let
        header =
            itemLine [] model.targetOutput

        content =
            [ div [ class "refinement-recipe" ]
                [ div [ class "refinement-inputs" ]
                    (List.indexedMap viewInputSlot model.inputSlots)
                , i [ class "material-icons modal-recipe-arrow" ]
                    [ text "arrow_right_alt" ]
                , div [ class "refinement-outputs" ]
                    (List.map (viewItemSpec [ class "output" ])
                        model.parent.outputs
                    )
                ]
            , div
                [ class "refinement-accept-button"
                , onClick (Messages.GridMsg (createAddMsg model))
                ]
                [ text "Accept" ]
            ]
    in
    withModal [ header ] content
