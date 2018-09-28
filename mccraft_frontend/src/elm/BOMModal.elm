module BOMModal exposing (Model, mkModel, view)

import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import IntDict exposing (IntDict)
import ItemRendering exposing (itemIcon)
import Messages
import ModalRendering exposing (withModal)
import PrimaryModel exposing (Item)


type alias Model =
    { items : IntDict Item
    , bom : IntDict Int
    }


mkModel =
    Model


view : Model -> Html Messages.Msg
view model =
    let
        header =
            [ div [ class "modal-header-text" ] [ text "Export" ] ]

        content =
            [ div [ class "bom-items" ] <| List.filterMap renderItem <| IntDict.keys model.bom ]

        renderItem key =
            Maybe.map2
                (\item count ->
                    div [ class "bom-item" ]
                        [ itemIcon [] item
                        , div [ class "bom-item-count" ] [ text <| String.fromInt count ]
                        ]
                )
                (IntDict.get key model.items)
                (IntDict.get key model.bom)
    in
    withModal header content
