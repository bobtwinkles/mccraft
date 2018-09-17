module Force exposing
    ( Entity
    , entity
    )


type alias Entity comparable a =
    { a
        | x : Float
        , y : Float
        , vx : Float
        , vy : Float
        , id : comparable
    }


entity : comparable -> a -> Entity comparable { label: a }
entity i v =
    { label = v, x = 0, y = 0, vx = 0, vy = 0, id = i }
