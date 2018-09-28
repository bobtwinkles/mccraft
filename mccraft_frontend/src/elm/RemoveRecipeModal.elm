module RemoveRecipeModal exposing (Model, mkModel, view)

import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import Messages
import ModalRendering exposing (withModal)


type alias Model =
    { recipe : Int
    }


mkModel : Int -> Model
mkModel =
    Model


view : Model -> Html Messages.Msg
view model =
    let
        header =
            [ div [ class "modal-header-text" ] [ text "Remove Recipe" ] ]

        content =
            [ div [] [ text "Are you sure you want to remove this recipe?" ]
            , div [ class "confirm-container" ]
                [ div
                    [ class "button"
                    , onClick (Messages.GridMsg <| Messages.RemoveRecipeFromGrid model.recipe)
                    ]
                    [ text "yes" ]
                , div
                    [ class "button"
                    , onClick Messages.ExitModal
                    ]
                    [ text "no" ]
                ]
            ]
    in
    withModal header content
