module ItemRendering exposing
    ( RenderableItem
    , itemIcon
    , itemLine
    , urlForItem
    )

import Html exposing (..)
import Html.Attributes exposing (..)
import Messages exposing (Msg)
import PrimaryModel exposing (ItemType)
import Url.Builder as UB



-- Rendering utilities


{-| Get the URL of the image that represents a given item
-}
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
        PrimaryModel.Fluid ->
            UB.relative
                [ "images"
                , "fluids"
                , String.append (String.replace ":" "_" ri.minecraftId) ".png"
                ]
                []

        PrimaryModel.ItemStack ->
            UB.relative [ "images", "items", formatMCID ri.minecraftId ] []

        PrimaryModel.UnknownType ->
            UB.relative [ "static", "ohno.png" ] []


{-| Render a detailed view of an item
-}
itemLine : List (Attribute Msg) -> RenderableItem a -> Html Msg
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


{-| Extensible record documenting what we need to actually render an item item
-}
type alias RenderableItem a =
    { a
        | minecraftId : String
        , itemName : String
        , ty : ItemType
    }


{-| Render the item iconified
-}
itemIcon : List (Attribute Msg) -> RenderableItem a -> Html Msg
itemIcon extraAttrs item =
    let
        myAttrs =
            [ class "item-icon"
            , class "mc-text"
            , src (urlForItem item)
            , alt item.itemName
            , title item.itemName
            ]
    in
    img (myAttrs ++ extraAttrs) [ text item.itemName ]
