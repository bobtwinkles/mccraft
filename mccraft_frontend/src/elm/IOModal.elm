module IOModal exposing
    ( ExportModal
    , ImportModal
    , mkExport
    , mkImport
    , updateImport
    , viewExport
    , viewImport
    )

import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import Messages
import ModalRendering exposing (withModal)


type alias ImportModal =
    { currentString : String
    }


type alias ExportModal =
    { jsonifiedGraph : String
    }


mkImport : ImportModal
mkImport =
    ImportModal ""


mkExport : String -> ExportModal
mkExport =
    ExportModal


updateImport : Messages.ImportModalMsg -> ImportModal -> ( ImportModal, Cmd Messages.Msg )
updateImport msg model =
    case msg of
        Messages.ImportTextAreaUpdated x ->
            ( { model | currentString = x }, Cmd.none )


viewImport : ImportModal -> Html Messages.Msg
viewImport model =
    let
        header =
            [ div [ class "modal-header-text" ] [ text "Import " ] ]

        content =
            [ textarea
                [ class "import-text-area"
                , onInput (Messages.ImportModalMsg << Messages.ImportTextAreaUpdated)
                ]
                []
            , div [ class "button", onClick (Messages.DoImport model.currentString) ] [ text "Import" ]
            ]
    in
    withModal header content


viewExport : ExportModal -> Html Messages.Msg
viewExport model =
    let
        header =
            [ div [ class "modal-header-text" ] [ text "Export" ] ]

        content =
            [ textarea [] [ text model.jsonifiedGraph ] ]
    in
    withModal header content
