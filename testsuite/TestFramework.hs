module TestFramework (

  assert_, assertEqual_, assertEqual2_, assertNotNull_, assertNull_,
  assertSeqEqual_,
  assertLambdabot_,

  tests, random, io80,

  HU.Test(..), runTestTT

) where

import Data.Char
import IO ( stderr )
import Data.List ( (\\) )
import Language.Haskell.TH
import qualified Test.HUnit as HU
import System.Random hiding (random)
import Test.QuickCheck

import Lambdabot.Process
import System.Directory
import qualified Control.OldException as E

type Location = (String, Int)

showLoc :: Location -> String
showLoc (f,n) = f ++ ":" ++ show n

assert_ :: Location -> Bool -> HU.Assertion
assert_ loc False = HU.assertFailure ("assert failed at " ++ showLoc loc)
assert_ loc True = return ()

-- lb
assertLambdabot_ :: Location -> String -> String -> HU.Assertion
assertLambdabot_ loc src expected = do
    actual <- echo src

    if expected /= actual
       then HU.assertFailure (msg actual)
       else return ()

    where msg a = "assertEqual failed at " ++ showLoc loc ++
                "\n expected: " ++ show expected ++ "\n but got:  " ++ show a

assertEqual_ :: (Eq a, Show a) => Location -> a -> a -> HU.Assertion
assertEqual_ loc expected actual =

    if expected /= actual
       then HU.assertFailure msg
       else return ()

    where msg = "assertEqual failed at " ++ showLoc loc ++
                "\n expected: " ++ show expected ++ "\n but got:  " ++ show actual

assertEqual2_ :: Eq a => Location -> a -> a -> HU.Assertion
assertEqual2_ loc expected actual =
    if expected /= actual
       then HU.assertFailure ("assertEqual2' failed at " ++ showLoc loc)
       else return ()

assertSeqEqual_ :: (Eq a, Show a) => Location -> [a] -> [a] -> HU.Assertion
assertSeqEqual_ loc expected actual =
    let ne = length expected
        na = length actual
        in case () of
            _| ne /= na ->
                 HU.assertFailure ("assertSeqEqual failed at " ++ showLoc loc
                                   ++ "\n expected length: " ++ show ne
                                   ++ "\n actual length: " ++ show na)
             | not (unorderedEq expected actual) ->
                 HU.assertFailure ("assertSeqEqual failed at " ++ showLoc loc
                                   ++ "\n expected: " ++ show expected
                                   ++ "\n actual: " ++ show actual)
             | otherwise -> return ()
    where unorderedEq l1 l2 =
              null (l1 \\ l2) && null (l2 \\ l1)


assertNotNull_ :: Location -> [a] -> HU.Assertion
assertNotNull_ loc [] = HU.assertFailure ("assertNotNull failed at " ++ showLoc loc)
assertNotNull_ _ (_:_) = return ()

assertNull_ :: Location -> [a] -> HU.Assertion
assertNull_ loc (_:_) = HU.assertFailure ("assertNull failed at " ++ showLoc loc)
assertNull_ loc [] = return ()


tests :: String -> Q [Dec] -> Q [Dec]
tests name decs =
    do decs' <- decs
       let ts = collectTests decs'
       e <- [| HU.TestLabel name (HU.TestList $(listE (map mkExp ts))) |]
       let lete = LetE decs' e
           suiteDec = ValD (VarP (mkName name)) (NormalB lete) []
           resDecs = [suiteDec]
       --runIO $ putStrLn (pprint resDecs)
       return resDecs
    where
    collectTests :: [Dec] -> [Name]
    collectTests [] = []
    collectTests (ValD (VarP name) _ _ : rest)
        | isTestName (nameBase name) = name : collectTests rest
    collectTests (_ : rest) = collectTests rest
    isTestName ('t':'e':'s':'t':_) = True
    isTestName _ = False
    mkExp :: Name -> Q Exp
    mkExp name =
        let s = nameBase name
            in [| HU.TestLabel s (HU.TestCase $(varE name)) |]


-- We use our own test runner, because HUnit print test paths a bit unreadable:
-- If a test list contains a named tests, then HUnit prints `i:n' where i
-- is the index of the named tests and n is the name.

{-
`runTestText` executes a test, processing each report line according
to the given reporting scheme.  The reporting scheme's state is
threaded through calls to the reporting scheme's function and finally
returned, along with final count values.
-}

runTestText :: HU.PutText st -> HU.Test -> IO (HU.Counts, st)
runTestText (HU.PutText put us) t = do
  put allTestsStr True us
  (counts, us') <- HU.performTest reportStart reportError reportFailure us t
  us'' <- put (HU.showCounts counts) True us'
  return (counts, us'')
 where
  allTestsStr = unlines ("All tests:" :
                         map (\p -> "  " ++ showPath p) (HU.testCasePaths t))
  reportStart ss us = put (HU.showCounts (HU.counts ss)) False us
  reportError   = reportProblem "Error:"   "Error in:   "
  reportFailure = reportProblem "Failure:" "Failure in: "
  reportProblem p0 p1 msg ss us = put line True us
   where line  = "### " ++ kind ++ path' ++ '\n' : msg
         kind  = if null path' then p0 else p1
         path' = showPath (HU.path ss)



{-
`showPath` converts a test case path to a string, separating adjacent
elements by ':'.  An element of the path is quoted (as with `show`)
when there is potential ambiguity.
-}

showPath :: HU.Path -> String
showPath [] = ""
showPath nodes = foldr1 f (map showNode (filterNodes (reverse nodes)))
 where f a b = a ++ ":" ++ b
       showNode (HU.ListItem n) = show n
       showNode (HU.Label label) = safe label (show label)
       safe s ss = if ':' `elem` s || "\"" ++ s ++ "\"" /= ss then ss else s
       filterNodes (HU.ListItem _ : l@(HU.Label _) : rest) =
           l : filterNodes rest
       filterNodes [] = []
       filterNodes (x:rest) = x : filterNodes rest

{-
`runTestTT` provides the "standard" text-based test controller.
Reporting is made to standard error, and progress reports are
included.  For possible programmatic use, the final counts are
returned.  The "TT" in the name suggests "Text-based reporting to the
Terminal".
-}

runTestTT :: HU.Test -> IO HU.Counts
runTestTT t = do (counts, 0) <- runTestText (HU.putTextToHandle stderr True) t
                 return counts

lambdabot     = "./lambdabot"
lambdabotHome = ".."

-- run the lambdabot
echo :: String -> IO String
echo cmd = E.handle (\e -> return (show e)) $ do
    p <- getCurrentDirectory
    setCurrentDirectory lambdabotHome
    let s = cmd ++ "\n"
    v <- eval lambdabot s clean
    setCurrentDirectory p
    return v
 where
    clean s = let f = drop 11 . reverse
              in case f (f s) of
                    [] -> []
                    x  -> init x

    eval :: FilePath -> String -> (String -> String) -> IO String
    eval binary src scrub = do
        (out,_,_) <- popen binary [] (Just src)
        return ( scrub out )

random :: Arbitrary a => IO a
random = do
    g <- getStdGen
    return $ generate 1000 g (arbitrary :: Arbitrary a => Gen a)

io80 :: IO String -> IO String
io80 f = take 80 `fmap` f

instance Arbitrary Char where
    -- filters ctrl chars, and chops lines too remember!
    arbitrary     = elements $ ['a'..'z'] ++ ['A' .. 'Z'] ++ ['0' .. '9']
    coarbitrary c = variant (ord c `rem` 4)

