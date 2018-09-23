module Messages exposing
    ( GridMsg(..)
    , Msg(..)
    , RecipeModalMsg(..)
    , SearchMsg(..)
    )

import Http
import PrimaryModel exposing (CompleteRecipe, Item, PartialRecipe)


type RecipeModalMsg
    = SendPartialRequest
    | ApplyPartials (List PartialRecipe)
    | SelectMachine Int
    | AddRecipe CompleteRecipe


type SearchMsg
    = SearchItem String
    | ItemSearchResults (List Item)


type GridMsg
    = AddItem Item


type Msg
    = SearchMsg SearchMsg
    | GridMsg GridMsg
      -- Recipe modal messages
    | PopRecipeModalFor Item
    | RecipeModalMsg RecipeModalMsg
    | CancelRecipeModal
      -- Error conditions
    | FlashError String
