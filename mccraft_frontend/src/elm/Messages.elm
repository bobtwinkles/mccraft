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
        , ItemSpec
        , PartialRecipe
        )


type RecipeModalMsg
    = SendPartialRequest
    | ApplyPartials (List PartialRecipe)
    | SelectMachine Int
    | AddRecipe CompleteRecipe


type RefineModalMsg
    = RefineToItem Int ItemSpec


type SearchMsg
    = SearchItem String
    | ItemSearchResults (List Item)


type
    GridMsg
    -- Add a recipe. First list is the inputs, second is the outputs
    = AddRecipeToGrid CompleteRecipe (List ItemSpec)


type Msg
    = SearchMsg SearchMsg
    | GridMsg GridMsg
      -- Recipe modal messages
    | PopRecipeModal Item
    | RecipeModalMsg RecipeModalMsg
      -- Refinement modal messages
    | PopRefinementModal Item DedupedRecipe
    | RefineModalMsg RefineModalMsg
      -- Error conditions
    | FlashError String
    | ExitModal
