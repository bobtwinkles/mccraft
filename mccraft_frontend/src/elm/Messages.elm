module Messages exposing
    ( GridMsg(..)
    , Msg(..)
    , RecipeModalMsg(..)
    , RefineModalMsg(..)
    , SearchMsg(..)
    )

import Http
import PrimaryModel
    exposing
        ( CompleteRecipe
        , DedupedRecipe
        , Item
        , PartialRecipe
        )


type RecipeModalMsg
    = SendPartialRequest
    | ApplyPartials (List PartialRecipe)
    | SelectMachine Int
    | AddRecipe CompleteRecipe


type RefineModalMsg
    = SelectItem Int Int


type SearchMsg
    = SearchItem String
    | ItemSearchResults (List Item)


type GridMsg
    = AddItem Item


type Msg
    = SearchMsg SearchMsg
    | GridMsg GridMsg
      -- Recipe modal messages
    | PopRecipeModal Item
    | RecipeModalMsg RecipeModalMsg
      -- Refinement modal messages
    | PopRefinementModal Item DedupedRecipe
      -- Error conditions
    | FlashError String
    | ExitModal
