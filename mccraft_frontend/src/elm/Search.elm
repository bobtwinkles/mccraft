module Search exposing (Model, mkModel, update, view)

import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import Http
import ItemRendering exposing (itemLine)
import Json.Decode as Decode
import Messages
import PrimaryModel exposing (Item, handleHttpError, itemDecoder)
import Url.Builder as UB



-- Model definition


type alias SearchResult =
    { item : Item
    }


type alias Model =
    { searchResults : List SearchResult
    }



-- Model constructors


mkSearchResult : Item -> SearchResult
mkSearchResult i =
    SearchResult i


mkModel : Model
mkModel =
    Model []



-- Update functions


doItemSearch : String -> Model -> ( Model, Cmd Messages.Msg )
doItemSearch term model =
    if String.length term < 3 then
        ( { model | searchResults = [] }, Cmd.none )

    else
        let
            url =
                UB.relative [ "search.json" ] [ UB.string "q" term ]

            processResponse x =
                case x of
                    Ok item ->
                        Messages.SearchMsg (Messages.ItemSearchResults item)

                    Err item ->
                        Messages.FlashError (handleHttpError item)
        in
        ( model, Http.send processResponse (Http.get url (Decode.list itemDecoder)) )


update : Messages.SearchMsg -> Model -> ( Model, Cmd Messages.Msg )
update msg model =
    case msg of
        Messages.SearchItem term ->
            doItemSearch term model

        Messages.ItemSearchResults res ->
            ( { model | searchResults = List.map mkSearchResult res }, Cmd.none )



-- View function


searchResult : Int -> SearchResult -> Html Messages.Msg
searchResult index result =
    itemLine
        [ class "search-result"
        , class
            (if modBy 2 index == 0 then
                "even"

             else
                "odd"
            )
        , onClick (Messages.PopRecipeModalFor result.item)
        ]
        result.item


view : Model -> Html Messages.Msg
view model =
    div [ class "primary-search-wrapper" ]
        [ input
            [ id "primary-search"
            , class "primary-search"
            , type_ "text"
            , placeholder "Item"
            , onInput (\x -> Messages.SearchMsg <| Messages.SearchItem x)
            ]
            []
        , div [ class "search-results" ] (List.indexedMap searchResult model.searchResults)
        ]
