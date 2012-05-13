module Main where

import System( getArgs )
import Char
import IO (readFile)
import List (nubBy, partition, intersperse, find)

import Debug.Trace

import Author.ParseLib

data Expr = Word Id
          | Quot [Expr]
          | Bool Bool
          | Pair Expr Expr
          | Chr Char
          | Num Int
          | Fun (Prog -> Prog)
          | Def Id [Expr]
          | Comm String

instance Eq Expr where
    Word w == Word x    =    w == x
    Num  n == Num  m    =    n == m
    Bool b == Bool c    =    b == c
    Chr  c == Chr  d    =    c == d
    Quot es == Quot xs  =    es == xs
    Pair e f == Pair x y =   e == x && x == y
    Fun _ == Fun _      =    error "Cannot compare functions"
    Def _ _ == Def _ _  =    error "Cannot compare definitions"
    _      == _         =    False
    

instance Show Expr where
    show (Word id) = id
    show (Num n) = show n
    show (Bool b) = '?' : show b
    show (Pair a b) = "(" ++ show a ++ " " ++ show b ++ ")"
    show (Chr c) = '.':c:[]
    show (Quot es) = case all typeIsChar es of
            True  -> "\"" ++ ( map (\(Chr c) -> c) es ) ++ "\""
            False -> "[" ++ (concat $ intersperse " " $ map show es) ++ "]"
        where
            typeIsChar (Chr _) = True
            typeIsChar _       = False
    show (Fun _) = "<function>"
    show (Def id es) = ""
    show (Comm s) = "" -- "-- " ++ s ++ "\n"


type Id = String
type Prog = [ Expr ]


digit :: Parser Char
digit = satisfy isDigit

letter :: Parser Char
letter = satisfy isAlpha

whiteSpace :: Parser Char
whiteSpace = satisfy (`elem` "\n\r \t")

strToQuote :: String -> Expr
strToQuote s = Quot (map Chr s)

token :: Parser a -> Parser a
token p = p <| ignoredChars
    where
        ignoredChars = maybeSome $ whiteSpace

keyword :: String -> Parser String
keyword = token . string

parseChar :: Parser Expr
parseChar = token $ pure Chr <*> char '.' |> anyChar

parseString :: Parser Expr
parseString = pure strToQuote <*> s
    where 
        s =  token ( char '`'  |> maybeSome ( satisfy (/= '`')  ) <| char '`' )
         <|> token ( char '"'  |> maybeSome ( satisfy (/= '"')  ) <| char '"' )
         <|> token ( char '\'' |> maybeSome ( satisfy (/= '\'') ) <| char '\'' )

parseNumber :: Parser Expr
parseNumber = pure Num <*> n
    where
        n = token $ pure (read) <*> atLeastOne digit

parseComment :: Parser Expr
parseComment = token $ pure Comm <*> keyword "--" |> ( maybeSome $ anyCharExcept "\n\r" ) <| ( maybeSome $ satisfy (`elem` "\n\r") )

parsePair :: Parser Expr
parsePair = pure Pair <*> keyword "(" |> parseExpr <*> parseExpr <| keyword ")"

parseId :: Parser String
parseId = token $ pure (:) <*> anyCharExcept reservedPrefixes <*> ( maybeSome $ anyCharExcept reservedChars )
    where
        reservedPrefixes = ".0123456789" ++ reservedChars
        reservedChars = " \t\n\r\0[]\"'`()"

parseBool :: Parser Expr
parseBool = pure Bool <*> ( pure read <*> ( keyword "True" <|> keyword "False" ) )

parseWord :: Parser Expr
parseWord = pure Word <*> parseId

parseQuot :: Parser Expr
parseQuot = token $ pure Quot <*> keyword "[" |> maybeSome parseExpr <| keyword "]"

parseExpr :: Parser Expr
parseExpr = parseComment <|> parseBool <|> parseChar <|> parseNumber <|> parseQuot <|> parsePair <|> parseString <|> parseWord

parse :: String -> [Expr]
parse s = case junk of
    ""        -> exps
    otherwise -> error ("Parse error in '" ++ take 30 junk ++ "...'\n")
    where
        (junk, exps) = head $ maybeSome parseExpr s

---------------------------------------------------------------------
-- Primitive functions
---------------------------------------------------------------------

-- Prog -> Prog

fnNot :: Prog -> Prog
fnNot  (Bool False:st) = Bool True:st
fnNot  (e:st) = Bool False:st

fnOr :: Prog -> Prog
fnOr (y:x:st) = case truthValueOf x of
    True  -> x:st
    False -> y:st
        
fnAnd :: Prog -> Prog
fnAnd (y:x:st) = case truthValueOf x of
    False -> x:st
    True  -> y:st

fnNull :: Prog -> Prog
fnNull (Quot []:st) = Bool True:st
fnNull (Quot q:st)  = Bool False:st
fnNull (e:st) = barf st ("Cannot determine if non-quote value '" ++ show e ++ "' is null.")

truthValueOf :: Expr -> Bool
truthValueOf (Bool False) = False
truthValueOf e = True

fnType :: Prog -> Prog
fnType st@(Quot _:_)   = strToQuote "quotation":st
fnType st@(Word _:_)   = strToQuote "word":st
fnType st@(Bool _:_)   = strToQuote "boolean":st
fnType st@(Chr _:_)    = strToQuote "character":st
fnType st@(Fun _:_)    = strToQuote "function":st
fnType st@(Num _:_)    = strToQuote "number":st
fnType st@(Pair _ _:_) = strToQuote "number":st

-- fnPutChar :: Prog -> Prog
-- fnPutChar (Chr c:st) = st


fnSplitAt (Num n:Quot es:st) = Quot as:Quot bs:st
    where
        (as, bs) = splitAt n es

-- fnFoldr (Quot fn:e:Quot es:st) = 

-- Prog -> Prog functions

fnDef :: Prog -> Prog
fnDef (Word id:Quot es:st) = (Def id es:st)

fnDip :: Prog -> Prog
fnDip (Quot q : e : st ) = (e:st')
    where
        (st') = fnApply (Quot q:st)

fnDig :: Prog -> Prog
fnDig (Num n:Quot q:st) = (es ++ st')
    where
        es = take n st
        (st') = fnApply (Quot q:(drop n st))

fnBury :: Prog -> Prog
fnBury (Num n:e:st) = es ++ (e:st')
    where
        (es, st') = splitAt n st

fnExhume :: Prog -> Prog
fnExhume (Num n:st) = (e:st')
    where
        (xs, e:ys) = splitAt n st
        st' = xs ++ ys

fnApply :: Prog -> Prog
fnApply (Fun f:st)     = descend $ f (st)
fnApply (Quot es:st)   = descend (es ++ st)
fnApply (e:st)         = barf st $ "Don't know how to apply " ++ show e

fnEval :: Prog -> Prog
fnEval []           = []
fnEval (Word w:st)  = case find (getDef w) st of
                          Nothing         -> (Word w:st)
                          Just (Def _ es) -> descend (es ++ st)
    where
        getDef w (Def id _) = id == w
        getDef w _ = False
fnEval t@(Fun f:st) = fnApply t
fnEval (Comm _:st)  = (st)
fnEval (e:st)       = (e:st)
 
fnError :: Prog -> Prog
fnError (msg:st) = barf st (show msg)

-- utility functions

descend :: Prog -> Prog
descend [] = []
descend (e:st) = fnEval (e:st')
    where
        st' = descend (st)

numericBinaryPrim :: (Int -> Int -> Int) -> Prog -> Prog
numericBinaryPrim f (Num x  : Num y  : st') = (Num  (f x y) : st')
numericBinaryPrim f st = Fun (numericBinaryPrim f):st

makeDef :: (String, Prog -> Prog) -> Expr
makeDef (id, f) = Def id [Fun f]


---------------------------------------------------------------------
-- Primitive definitions
---------------------------------------------------------------------
progFunctions = [
    ( "drop", \(e:st) -> st ),
    -- ( "swap", \(e:f:st) -> f:e:st ),
    -- ( "rot",  \(e:f:g:st) -> g:e:f:st ),
    -- ( "unrot",  \(e:f:g:st) -> f:g:e:st ),
    ( "dup",  \(e:st) -> e:e:st ),
    ( "bury", fnBury ),
    ( "exhume", fnExhume ),

    ( "=",    \(e:f:st) -> Bool (e == f):st ),
    ( "not",  fnNot ),
    ( "or",   fnOr ),
    ( "and",  fnAnd ),

    ( "quote",   \(e:st) -> Quot [e]:st ),
    ( "cons",    \(e:Quot es:st) -> Quot (e:es):st ),
    ( "uncons",  \(Quot (e:es):st) -> e:Quot es:st ),
    ( "splitAt", fnSplitAt ),
    ( "null",    fnNull ),
    ( "append",  \(Quot b:Quot a:st) -> Quot (a ++ b):st ),

    ( "show",    \(e:st) -> (strToQuote $ show e):st ),
    ( "type",    fnType ),

    ("dip", fnDip),
    ("dig", fnDig),
    ("apply", fnApply),

    ("+", numericBinaryPrim (+)),
    ("-", numericBinaryPrim (-)),
    ("*", numericBinaryPrim (*)),
    ("/", numericBinaryPrim div),
    ("%", numericBinaryPrim mod),

    ("croak",  fnError ),

    ("def", fnDef ) ]

prims = map makeDef progFunctions




---------------------------------------------------------------------
-- Argument processing and main
---------------------------------------------------------------------

barf :: Prog -> String -> a
barf st msg = error $ "** Error: " ++ msg ++ "\nAt\n   " ++ showAst st ++ "\n\n"

showAst :: Prog -> String
showAst st = ( take 150 $ show $ Quot st ) ++ ( if length st > 150 then "..." else "" )


main :: IO ()
main = do
    args <- getArgs
    sources <- mapM readFile (args ++ ["headstone.fn"])
    let prog = ( parse $ concat sources ) ++ prims
    putStrLn $ show $ descend $ trace (showAst prog) prog

