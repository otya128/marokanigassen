{-# LANGUAGE GeneralizedNewtypeDeriving #-}

module Language.MaroKani.Parser
( parse
, T.Result(..)
) where

import Language.MaroKani.Types

import Control.Applicative
import qualified Text.Trifecta as T
import qualified Text.Parser.Token.Style as TS
import qualified Data.HashSet as HashSet
import Data.Monoid (mempty)

cStyle :: TS.CommentStyle
cStyle = TS.CommentStyle "/*" "*/" "" True

newtype Parser a = Parser { runParser :: T.Parser a }
  deriving (Functor,Applicative,Alternative,Monad,T.Parsing,T.CharParsing)

instance T.TokenParsing Parser where
  nesting (Parser m) = Parser (T.nesting m)
  someSpace = TS.buildSomeSpaceParser (Parser T.someSpace) cStyle
  semi = Parser T.semi
  highlight h (Parser m) = Parser (T.highlight h m)

idStyle :: T.IdentifierStyle Parser
idStyle = TS.emptyIdents
  { T._styleReserved = HashSet.fromList ["_","if","then","else"] }

opStyle :: T.IdentifierStyle Parser
opStyle = TS.emptyOps
  { T._styleLetter = T.oneOf ":!#$%&*+./<=>?@^|-~"
  , T._styleReserved = HashSet.fromList ["=",":=",".","/*","*/"] }

addParens :: String -> String
addParens s = "(" ++ s ++ ")"

addBrackets :: String -> String
addBrackets s = "[" ++ s ++ "]"

var :: Parser String
var = T.ident idStyle
  <|> (addParens <$> T.parens (T.ident opStyle))
  <|> (addBrackets <$> T.brackets (T.ident opStyle))

value :: Parser Value
value = (either VInt VDouble <$> T.naturalOrDouble)
  <|> (VString <$> T.stringLiteral)
  <|> (VBool False <$ T.symbol "()")
  <|> (mkFun <$ T.symbol "\\" <*> some (var <|> T.symbol "_") <*> T.braces exprs)
  where
    mkFun [] es = Fun Nothing "_" es
    mkFun [v] es = Fun Nothing v es
    mkFun (v:vs) es = Fun Nothing v [EValue $ mkFun vs es]

mk2ArgsOper :: String -> Parser (Expr -> Expr -> Expr)
mk2ArgsOper name = return $ \x y -> Var (addParens name) `App` x `App` y

oper :: Char -> Parser (Expr -> Expr -> Expr)
oper c = do
  name <- T.ident opStyle { T._styleStart = T.char c }
  mk2ArgsOper name

opers :: String -> Parser (Expr -> Expr -> Expr)
opers = foldr (<|>) empty . map oper

unaryOper :: Parser Expr
unaryOper = do
  name <- T.ident opStyle
  e <- expr
  return $ App (Var $ addBrackets name) e

fact :: Parser Expr
fact = T.try (Var <$> var)
  <|> (EValue <$> value)
  <|> T.try (T.brackets $ mk2ArgsOper "(--->)" <*> expr <* T.symbol ",," <*> expr)
  <|> (T.brackets $ EArray <$> T.commaSep1 expr)
  <|> (T.braces $ EObject <$> (T.commaSep $ (,) <$> var <* T.symbol ":=" <*> expr))
  <|> T.parens expr

unary :: Parser Expr
unary = fact <|> unaryOper

app :: Parser Expr
app = foldl App <$> unary <*> many fact

dotSharp :: Parser Expr
dotSharp = app `T.chainl1` opers ".#"

power :: Parser Expr
power = dotSharp `T.chainr1` opers "^"

mulDiv :: Parser Expr
mulDiv = power `T.chainl1` opers "*/%"

addSub :: Parser Expr
addSub = mulDiv `T.chainl1` opers "+-:@"

backQuote :: Parser Expr
backQuote = T.chainl1 addSub $ T.try $ do
  e <- T.between (T.symbol "`") (T.symbol "`") expr
  return $ \a b -> e `App` a `App` b

comp :: Parser Expr
comp = backQuote `T.chainl1` opers "=!<>~"

parseAnd :: Parser Expr
parseAnd = comp `T.chainl1` opers "&"

parseOr :: Parser Expr
parseOr = parseAnd `T.chainl1` opers "|"

dollar :: Parser Expr
dollar = parseOr `T.chainr1` opers "$?"

asgn :: Parser Expr
asgn = T.try (Asgn <$> var <* T.symbol "=" <*> expr)
  <|> T.try (Decl <$> var <* T.symbol ":=" <*> expr)
  <|> T.try (ConstDecl <$> var <* T.symbol "::=" <*> expr)
  <|> dollar

parseIf :: Parser Expr
parseIf = If <$ T.symbol "if" <*> expr
  <* T.symbol "then" <*> expr
  <*> optional (T.symbol "else" *> expr)

expr :: Parser Expr
expr = parseIf <|> asgn

exprs :: Parser [Expr]
exprs = optional T.someSpace *> T.sepEndBy expr T.semi

parse :: String -> T.Result [Expr]
parse s = T.parseString (runParser exprs) mempty s
