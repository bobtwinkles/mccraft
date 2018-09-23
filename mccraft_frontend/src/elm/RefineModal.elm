module RefineModal exposing (Model, mkModel, update, view)

import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import ItemRendering exposing (itemIcon, itemLine)
import Messages exposing (RefineModalMsg)
import PrimaryModel exposing (DedupedRecipe, InputSlot, Item, ItemSpec)



-- Types


type alias Model =
    { targetOutput : Item
    , recipe : DedupedRecipe
    }



-- Initialization functions


mkModel : Item -> DedupedRecipe -> Model
mkModel =
    Model



-- Update functiosn


update : RefineModalMsg -> Model -> ( Model, Cmd Messages.Msg )
update msg model =
    case msg of
        Messages.SelectItem slotId newIndex ->
            ( model, Cmd.none )



-- View functions


viewItemSpec : ItemSpec -> Html Messages.Msg
viewItemSpec is =
    div [ class "refinement-item-spec" ]
        [ itemIcon [] is.item
        , div [] [ text (String.fromInt is.quantity) ]
        ]


viewInputSlot : InputSlot -> Html Messages.Msg
viewInputSlot is =
    div [ class "refinement-input-slot" ]
        ([ div [ class "refinement-input-slot-scale" ]
            [ text (String.fromInt is.scale) ]
         ]
            ++ List.map viewItemSpec is.itemSpecs
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
                [ div [ class "refinement-inputs" ] (List.map viewInputSlot model.recipe.inputSlots)
                , i [ class "material-icons modal-recipe-arrow" ] [ text "arrow_right_alt" ]
                , div [ class "refinement-outputs" ] (List.map viewItemSpec model.recipe.outputs)
                ]
            ]
        ]
