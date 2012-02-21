{-# LANGUAGE TemplateHaskell, MultiParamTypeClasses #-}
-- Copyright (c) Zach Kelling - http://github.com/zeekay
-- GPL version 2 or later (see http://www.gnu.org/copyleft/gpl.html)

-- | Provides The Zen of Haskell
module Plugin.Zen where

import Plugin

$(plugin "Zen")

instance Module ZenModule () where
    moduleCmds   _ = ["zen"]
    moduleHelp _ _ = "The Zen of Haskell"
    process_ _ _ _ = ios . return $ concat
                [ x++"\n" | x <- [ "Beautiful is better than ugly."
                                 , "Abstract is better than concrete."
                                 ,  "Block is better than bracket."
                                 ,  "Curry is better than uncurry."
                                 ,  "Free is better than bind."
                                 ,  "Lazy is better than crazy."
                                 ,  "Matched is better than unmatched."
                                 ,  "Pattern is better than condition."
                                 ,  "Regular is better than irregular."
                                 ,  "Solution is better than illusion."
                                 ,  "Universal is better than special."
                                 ,  "Arrow is one of those great ideas -- Let's go to find more of those!"
                                 ]]
