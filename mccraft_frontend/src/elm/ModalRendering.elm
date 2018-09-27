module ModalRendering exposing (withModal)

import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import Messages exposing (Msg)


withModal : List (Html Msg) -> List (Html Msg) -> Html Msg
withModal header content =
    let
        closeButton =
            i
                [ class "material-icons modal-close"
                , onClick Messages.ExitModal
                ]
                [ text "close" ]
    in
    div [ class "modal" ]
        [ div [ class "modal-content" ]
            (div [ class "modal-header" ] (header ++ [ closeButton ]) :: content)
        ]
