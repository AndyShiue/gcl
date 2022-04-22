{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}

module Syntax.Parser2 where

import           Control.Monad.Combinators.Expr
import           Control.Monad.Except
import qualified Data.Either                   as Either
import           Data.List.NonEmpty             ( NonEmpty )
import           Data.Loc
import           Data.Loc.Range
import           Data.Text                      ( Text )
import qualified Data.Text                     as Text
import           Data.Void
import           Language.Lexer.Applicative     ( TokenStream(TsEof, TsToken) )
import           Prelude                 hiding ( EQ
                                                , GT
                                                , LT
                                                , Ordering
                                                , lookup
                                                )
import           Syntax.Common           hiding ( Fixity(..) )
import           Syntax.Concrete         hiding ( Op )
import qualified Syntax.Concrete.Types         as Expr
import           Syntax.Parser2.Error
import           Syntax.Parser2.Lexer
import           Syntax.Parser2.Util     hiding ( Parser )
import           Text.Megaparsec         hiding ( ParseError
                                                , Pos
                                                , State
                                                , Token
                                                , parse
                                                , tokens
                                                )
import qualified Text.Megaparsec               as Mega

--------------------------------------------------------------------------------
-- | States for source location bookkeeping
type Parser = ParsecT Void TokStream M

--------------------------------------------------------------------------------

scanAndParse :: Parser a -> FilePath -> Text -> Either ParseError a
scanAndParse parser filepath source = case scan filepath source of
  Left  err    -> throwError (LexicalError err)
  Right tokens -> case parse parser filepath tokens of
    Left  errors -> throwError (SyntacticError errors)
    Right val    -> return val

parse :: Parser a -> FilePath -> TokStream -> Either (NonEmpty (Loc, String)) a
parse parser filepath tokenStream =
  case runM (runParserT (parser <* many dedent <* eof) filepath tokenStream) of
    Left  e -> Left (fromParseErrorBundle e)
    Right x -> Right x
 where
  fromParseErrorBundle
    :: ShowErrorComponent e
    => ParseErrorBundle TokStream e
    -> NonEmpty (Loc, String)
  fromParseErrorBundle (ParseErrorBundle errors _) = fmap toError errors
   where
    toError
      :: ShowErrorComponent e => Mega.ParseError TokStream e -> (Loc, String)
    toError err = (getLoc' err, parseErrorTextPretty err)
    -- get the Loc of all unexpected tokens
    getLoc' :: ShowErrorComponent e => Mega.ParseError TokStream e -> Loc
    getLoc' (TrivialError _ (Just (Tokens xs)) _) = foldMap locOf xs
    getLoc' _ = mempty

parseWithTokList
  :: Parser a -> FilePath -> [L Tok] -> Either (NonEmpty (Loc, String)) a
parseWithTokList parser filepath = parse parser filepath . convert
 where
  convert :: [L Tok] -> TokStream
  convert (x : xs) = TsToken x (convert xs)
  convert []       = TsEof

declOrDefnBlock :: Parser (Either Declaration DefinitionBlock)
declOrDefnBlock = choice
  [ Left <$> declaration <?> "declaration"
  , Right <$> definitionBlock <?> "definition block"
  ]


--------------------------------------------------------------------------------

-- | Parser for SepByComma
sepBy' :: Parser (Token sep) -> Parser a -> Parser (SepBy sep a)
sepBy' delim parser = do
  x <- parser

  let f = return (Head x)
  let g = do
        sep <- delim
        xs  <- sepBy' delim parser
        return $ Delim x sep xs
  try g <|> f

sepByComma :: Parser a -> Parser (SepBy "," a)
sepByComma = sepBy' tokenComma

sepByGuardBar :: Parser a -> Parser (SepBy "|" a)
sepByGuardBar = sepBy' tokenGuardBar

-- for building parsers for tokens
adapt :: Tok -> String -> Parser (Token a)
adapt t errMsg = do
  loc <- symbol t <?> errMsg
  case loc of
    NoLoc   -> error "NoLoc when parsing token"
    Loc l r -> return $ Token l r

tokenConst :: Parser (Token "con")
tokenConst = adapt TokCon "reserved word \"con\""

tokenVar :: Parser (Token "var")
tokenVar = adapt TokVar "reserved word \"var\""

tokenData :: Parser (Token "data")
tokenData = adapt TokData "reserved word \"data\""

tokenBraceOpen :: Parser (Token "{")
tokenBraceOpen = adapt TokBraceOpen "opening curly bracket"

tokenBraceClose :: Parser (Token "}")
tokenBraceClose = adapt TokBraceClose "closing curly bracket"

tokenBracketOpen :: Parser (Token "[")
tokenBracketOpen = adapt TokBracketOpen "opening square bracket"

tokenBracketClose :: Parser (Token "]")
tokenBracketClose = adapt TokBracketClose "closing square bracket"

tokenParenOpen :: Parser (Token "(")
tokenParenOpen = adapt TokParenOpen "opening parenthesis"

tokenParenClose :: Parser (Token ")")
tokenParenClose = adapt TokParenClose "closing parenthesis"

tokenQuantOpen :: Parser (Token "<|")
tokenQuantOpen = adapt TokQuantOpen "<|"

tokenQuantOpenU :: Parser (Token "⟨")
tokenQuantOpenU = adapt TokQuantOpenU "⟨"

tokenQuantClose :: Parser (Token "|>")
tokenQuantClose = adapt TokQuantClose "|>"

tokenQuantCloseU :: Parser (Token "⟩")
tokenQuantCloseU = adapt TokQuantCloseU "⟩"

tokenSpecOpen :: Parser (Token "[!")
tokenSpecOpen = adapt TokSpecOpen "[!"

tokenSpecClose :: Parser (Token "!]")
tokenSpecClose = adapt TokSpecClose "!]"

tokenProofOpen :: Parser (Token "{-")
tokenProofOpen = adapt TokProofOpen "{-"

tokenProofClose :: Parser (Token "-}")
tokenProofClose = adapt TokProofClose "-}"

tokenBlockOpen :: Parser (Token "|[")
tokenBlockOpen = adapt TokBlockOpen "|["

tokenBlockClose :: Parser (Token "]|")
tokenBlockClose = adapt TokBlockClose "]|"

tokenDeclOpen :: Parser (Token "{:")
tokenDeclOpen = adapt TokDeclOpen "{:"

tokenDeclClose :: Parser (Token ":}")
tokenDeclClose = adapt TokDeclClose ":}"

tokenColon :: Parser (Token ":")
tokenColon = adapt TokColon "colon"

tokenComma :: Parser (Token ",")
tokenComma = adapt TokComma "comma"

tokenRange :: Parser (Token "..")
tokenRange = adapt TokRange ".."

tokenStar :: Parser (Token "*")
tokenStar = adapt TokMul "*"

tokenArray :: Parser (Token "array")
tokenArray = adapt TokArray "reserved word \"array\""

tokenOf :: Parser (Token "of")
tokenOf = adapt TokOf "reserved word \"of\""

tokenBnd :: Parser (Token "bnd")
tokenBnd = adapt TokBnd "reserved word \"bnd\""

tokenIf :: Parser (Token "if")
tokenIf = adapt TokIf "reserved word \"if\""

tokenFi :: Parser (Token "fi")
tokenFi = adapt TokFi "reserved word \"fi\""

tokenDo :: Parser (Token "do")
tokenDo = adapt TokDo "reserved word \"do\""

tokenOd :: Parser (Token "od")
tokenOd = adapt TokOd "reserved word \"od\""

tokenCase :: Parser (Token "case")
tokenCase = adapt TokCase "reserved word \"case\""

tokenNew :: Parser (Token "new")
tokenNew = adapt TokNew "reserved word \"new\""

tokenDispose :: Parser (Token "dispose")
tokenDispose = adapt TokDispose "reserved word \"dispose\""

tokenQuestionMark :: Parser (Token "?")
tokenQuestionMark = adapt TokQM "?"

tokenAssign :: Parser (Token ":=")
tokenAssign = adapt TokAssign ":="

tokenEQ :: Parser (Token "=")
tokenEQ = adapt TokEQ "="

tokenGuardBar :: Parser (Token "|")
tokenGuardBar = adapt TokGuardBar "|"

tokenArrow :: Parser (Either (Token "->") (Token "→"))
tokenArrow =
  choice [Left <$> adapt TokArrow "->", Right <$> adapt TokArrowU "→"]

tokenUnderscore :: Parser (Token "_")
tokenUnderscore = adapt TokUnderscore "underscore \"_\""

--------------------------------------------------------------------------------
-- Declaration 
--------------------------------------------------------------------------------

declaration :: Parser Declaration
declaration = choice [constDecl, varDecl] <?> "declaration"

constDecl :: Parser Declaration
constDecl = ConstDecl <$> tokenConst <*> declType upper

varDecl :: Parser Declaration
varDecl = VarDecl <$> tokenVar <*> declType lower

-- `n : type` | `n : type { expr }` | `T a1 a2 ... = C1 ai1 ai2 .. | C2 ... | ...` | `n args = expr`
definition :: Parser Definition
definition = choice [try funcDefnSig, typeDefn, funcDefnF]
 where

  funcDefnSig :: Parser Definition
  funcDefnSig = FuncDefnSig <$> declBase identifier <*> optional declProp

  funcDefnF :: Parser Definition
  funcDefnF = FuncDefn <$> identifier <*> many lower <*> tokenEQ <*> expression

  -- `T a1 a2 ... = C1 ai1 ai2 .. | C2 ... | ...`
  typeDefn :: Parser Definition
  typeDefn =
    TypeDefn
      <$> tokenData
      <*> identifier
      <*> many identifier
      <*> tokenEQ
      <*> sepBy' ordinaryBar typeDefnCtor

  typeDefnCtor :: Parser TypeDefnCtor
  typeDefnCtor = TypeDefnCtor <$> identifier <*> many type'

definitionBlock :: Parser DefinitionBlock
definitionBlock =
  DefinitionBlock
    <$> tokenDeclOpen
    <*  many (ignoreP indentationRelated)
    <*> sepBy definition newlines
    <*  many (ignoreP indentationRelated)
    <*> tokenDeclClose

-- `n : type`
declBase :: Parser Name -> Parser DeclBase
declBase name = DeclBase <$> sepByComma name <*> tokenColon <*> type'

-- `{ expr }`
declProp :: Parser DeclProp
declProp = DeclProp <$> tokenBraceOpen <*> expression <*> tokenBraceClose

-- `n : type` | `n : type { expr }`
declType :: Parser Name -> Parser DeclType
declType name = DeclType <$> declBase name <*> optional declProp

--------------------------------------------------------------------------------
-- Statement 
--------------------------------------------------------------------------------

statement :: Parser Stmt
statement =
  choice
      [ skip
      , proofAnchors
      , abort
      , try assertion
      , loopInvariant
      , try assignment
      , try arrayAssignment
      , try alloc
      , try lookup
      , mutate
      , dispose
      , loop
      , conditional
      , hole
      , spec
      , programBlock
      ]
    -- [ try assignment,
    --   abort,
    --   try loopInvariant,
    --   spec,
    --   proofAnchors,
    --   assertion,
    --   skip,
    --   loop,
    --   conditional,
    --   hole
    -- ]
    <?> "statement"

-- ZERO or more statements
statements :: Parser [Stmt]
statements = sepBy statement newlines

-- ONE or more statements
statements1 :: Parser [Stmt]
statements1 = sepBy1 statement newlines

skip :: Parser Stmt
skip = withRange $ Skip <$ symbol TokSkip

abort :: Parser Stmt
abort = withRange $ Abort <$ symbol TokAbort

assertion :: Parser Stmt
assertion = Assert <$> tokenBraceOpen <*> expression <*> tokenBraceClose

loopInvariant :: Parser Stmt
loopInvariant = do
  LoopInvariant
    <$> tokenBraceOpen
    <*> predicate
    <*> tokenComma
    <*> tokenBnd
    <*> tokenColon
    <*> expression
    <*> tokenBraceClose

assignment :: Parser Stmt
assignment =
  Assign <$> sepByComma lower <*> tokenAssign <*> sepByComma expression

arrayAssignment :: Parser Stmt
arrayAssignment =
  AAssign
    <$> lower
    <*> tokenBracketOpen
    <*> expression
    <*> tokenBracketClose
    <*> tokenAssign
    <*> expression


loop :: Parser Stmt
loop = block' Do tokenDo (sepByGuardBar guardedCommand) tokenOd

conditional :: Parser Stmt
conditional = block' If tokenIf (sepByGuardBar guardedCommand) tokenFi

-- guardedCommands :: Parser [GdCmd]
-- guardedCommands = sepBy1 guardedCommand $ do
--   symbol TokGuardBar <?> "|"

guardedCommand :: Parser GdCmd
guardedCommand = GdCmd <$> predicate <*> tokenArrow <*> blockOf statement

hole :: Parser Stmt
hole = SpecQM <$> (rangeOf <$> tokenQuestionMark)

spec :: Parser Stmt
spec =
  Spec
    <$> tokenSpecOpen
    <*> takeWhileP (Just "anything other than '!]'") notTokSpecClose
    <*> tokenSpecClose
 where
  notTokSpecClose :: L Tok -> Bool
  notTokSpecClose (L _ TokSpecClose) = False
  notTokSpecClose _                  = True

proofAnchors :: Parser Stmt
proofAnchors =
  Proof
    <$> tokenProofOpen
    <*> many proofAnchor
    <*  optional newlines
    <*> tokenProofClose
 where
  proofAnchor :: Parser ProofAnchor
  proofAnchor = do
    (hash, range) <- getRange $ extract extractHash
    skipProof
    return $ ProofAnchor hash range

  skipProof :: Parser ()
  skipProof = void $ takeWhileP
    (Just "anything other than '-]' or another proof anchor")
    notTokProofCloseOrProofAnchor

  notTokProofCloseOrProofAnchor :: L Tok -> Bool
  notTokProofCloseOrProofAnchor (L _ TokProofClose     ) = False
  notTokProofCloseOrProofAnchor (L _ (TokProofAnchor _)) = False
  notTokProofCloseOrProofAnchor _                        = True

  extractHash (TokProofAnchor s) = Just (Text.pack s)
  extractHash _                  = Nothing

alloc :: Parser Stmt
alloc =
  Alloc
    <$> lower
    <*> tokenAssign
    <*> tokenNew
    <*> tokenParenOpen
    <*> sepByComma expression
    <*> tokenParenClose


lookup :: Parser Stmt
lookup = HLookup <$> lower <*> tokenAssign <*> tokenStar <*> expression

mutate :: Parser Stmt
mutate = HMutate <$> tokenStar <*> expression <*> tokenAssign <*> expression

dispose :: Parser Stmt
dispose = Dispose <$> tokenDispose <*> expression

programBlock :: Parser Stmt
programBlock =
  Block
    <$> tokenBlockOpen
    <*  many (ignoreP indentationRelated)
    <*> program
    <*  many (ignoreP indentationRelated)
    <*> tokenBlockClose

indentationRelated :: Tok -> Bool
indentationRelated TokIndent = True
indentationRelated TokDedent = True
indentationRelated _         = False

program :: Parser Program
program = do
  void $ optional newlines

  mixed <- sepBy (choice [Left <$> declOrDefnBlock, Right <$> statement])
                 newlines

  let (decls, stmts) = Either.partitionEithers mixed

  void $ optional newlines

  return $ Program decls stmts



newlines :: Parser ()
newlines = void $ some (symbol TokNewline)

dedent :: Parser ()
dedent = void $ symbol TokDedent

indent :: Parser ()
indent = void $ symbol TokIndent

--------------------------------------------------------------------------------
-- Expression 
--------------------------------------------------------------------------------

predicate :: Parser Expr
predicate = expression <?> "predicate"

expression :: Parser Expr
expression = makeExprParser (term <|> caseOf) chainOpTable <?> "expression"
 where
  chainOpTable :: [[Operator Parser Expr]]
  chainOpTable =
    [ -- =
      [InfixL $ binary (ChainOp . EQ) TokEQ]
      -- ~, <, <=, >, >=
    , [ InfixL $ binary (ChainOp . NEQ) TokNEQ
      , InfixL $ binary (ChainOp . NEQU) TokNEQU
      , InfixL $ binary (ChainOp . LT) TokLT
      , InfixL $ binary (ChainOp . LTE) TokLTE
      , InfixL $ binary (ChainOp . LTEU) TokLTEU
      , InfixL $ binary (ChainOp . GT) TokGT
      , InfixL $ binary (ChainOp . GTE) TokGTE
      , InfixL $ binary (ChainOp . GTEU) TokGTEU
      ]
      -- &&
    , [ InfixL $ binary (ArithOp . Conj) TokConj
      , InfixL $ binary (ArithOp . ConjU) TokConjU
      ]
      --- ||
    , [ InfixL $ binary (ArithOp . Disj) TokDisj
      , InfixL $ binary (ArithOp . DisjU) TokDisjU
      ]
      -- =>
    , [ InfixL $ binary (ArithOp . Implies) TokImpl
      , InfixL $ binary (ArithOp . ImpliesU) TokImplU
      ]
      -- <=>
    , [ InfixL $ binary (ChainOp . EQProp) TokEQProp
      , InfixL $ binary (ChainOp . EQPropU) TokEQPropU
      ]
    ]

  unary :: (Loc -> Op) -> Tok -> Parser (Expr -> Expr)
  unary operator' tok = do
    loc <- symbol tok
    return $ \result -> App (Expr.Op (operator' loc)) result

  binary :: (Loc -> Op) -> Tok -> Parser (Expr -> Expr -> Expr)
  binary operator' tok = do
    (op, loc) <- getLoc (operator' <$ symbol tok)
    return $ \x y -> App (App (Expr.Op (op loc)) x) y

  parensExpr :: Parser Expr
  parensExpr = Paren <$> tokenParenOpen <*> expression <*> tokenParenClose

  caseOf :: Parser Expr
  caseOf = Case <$> tokenCase <*> expression <*> tokenOf <*> blockOf caseClause


  caseClause :: Parser CaseClause
  caseClause = CaseClause <$> pattern' <*> tokenArrow <*> block expression

  term :: Parser Expr
  term = makeExprParser term' arithTable
   where
    arithTable :: [[Operator Parser Expr]]
    arithTable =
      [ [Prefix $ unary (ArithOp . NegNum) TokSub]
      , [InfixN $ binary (ArithOp . Exp) TokExp]
      , [ InfixN $ binary (ArithOp . Max) TokMax
        , InfixN $ binary (ArithOp . Min) TokMin
        ]
      , [InfixL $ binary (ArithOp . Mod) TokMod]
      , [ InfixL $ binary (ArithOp . Mul) TokMul
        , InfixL $ binary (ArithOp . Div) TokDiv
        ]
      , [ InfixL $ binary (ArithOp . Add) TokAdd
        , InfixL $ binary (ArithOp . Sub) TokSub
        ]
      , [ Prefix $ unary (ArithOp . Neg) TokNeg
        , Prefix $ unary (ArithOp . NegU) TokNegU
        ]
      ]

    term' :: Parser Expr
    term' =
      choice
          [ Lit <$> literal
          , try array
          , combineWithApp <$> parensExpr <*> many singleterm'
          , combineWithApp <$> (Var <$> lower) <*> many singleterm'
          , combineWithApp <$> (Const <$> upper) <*> many singleterm'
          , Quant
          <$> choice [Left <$> tokenQuantOpen, Right <$> tokenQuantOpenU]
          <*> choice [Left <$> operator, Right <$> term']
          <*> some lower
          <*> tokenColon
          <*> expression
          <*> tokenColon
          <*> expression
          <*> choice [Left <$> tokenQuantClose, Right <$> tokenQuantCloseU]
          ]
        <?> "term"
      where
        -- | Handling application,e.g., letting "f 1+2" to be parsed as '(f 1)+2'
        combineWithApp :: Expr -> [Expr] -> Expr
        combineWithApp = foldl App
    
    singleterm' :: Parser Expr
    singleterm' =
      choice
          [ Lit <$> literal
          , try array
          , parensExpr
          , Var <$> lower
          , Const <$> upper
          , Quant
          <$> choice [Left <$> tokenQuantOpen, Right <$> tokenQuantOpenU]
          <*> choice [Left <$> operator, Right <$> term']
          <*> some lower
          <*> tokenColon
          <*> expression
          <*> tokenColon
          <*> expression
          <*> choice [Left <$> tokenQuantClose, Right <$> tokenQuantCloseU]
          ]
        <?> "term"

    -- shoule parse A[A[i]], A[i1][i2]...[in]
    array :: Parser Expr
    array = do
      arr     <- choice [parensExpr, Var <$> lower, Const <$> upper]
      indices <- some $ do
        open  <- tokenBracketOpen
        xs    <- term
        close <- tokenBracketClose
        return (open, xs, close)
      return $ helper arr indices
     where
      helper :: Expr -> [(Token "[", Expr, Token "]")] -> Expr
      helper a []               = a
      helper a ((o, x, c) : xs) = helper (Arr a o x c) xs

  operator :: Parser Op
  operator = choice [ChainOp <$> chainOp, ArithOp <$> arithOp] <?> "operator"
   where
    chainOp :: Parser ChainOp
    chainOp = choice
      [ EQProp <$> symbol TokEQProp
      , EQPropU <$> symbol TokEQPropU
      , EQ <$> symbol TokEQ
      , NEQ <$> symbol TokNEQ
      , NEQU <$> symbol TokNEQU
      , LTE <$> symbol TokLTE
      , LTEU <$> symbol TokLTEU
      , GTE <$> symbol TokGTE
      , GTEU <$> symbol TokGTEU
      , LT <$> symbol TokLT
      , GT <$> symbol TokGT
      ]

    arithOp :: Parser ArithOp
    arithOp = choice
      [ Implies <$> symbol TokImpl
      , ImpliesU <$> symbol TokImplU
      , Conj <$> symbol TokConj
      , ConjU <$> symbol TokConjU
      , Disj <$> symbol TokDisj
      , DisjU <$> symbol TokDisjU
      , Neg <$> symbol TokNeg
      , NegU <$> symbol TokNegU
      , Add <$> symbol TokAdd
      , Sub <$> symbol TokSub
      , Mul <$> symbol TokMul
      , Div <$> symbol TokDiv
      , Mod <$> symbol TokMod
      , Max <$> symbol TokMax
      , Min <$> symbol TokMin
      , Exp <$> symbol TokExp
      , Add <$> symbol TokSum
      , Mul <$> symbol TokProd
      , Conj <$> symbol TokForall
      , Disj <$> symbol TokExist
      , Hash <$> symbol TokHash
      ]

-- TODO: LitChar 
literal :: Parser Lit
literal =
  withRange
      (choice
        [ LitBool True <$ symbol TokTrue
        , LitBool False <$ symbol TokFalse
        , LitInt <$> integer
        , LitChar <$> character
        ]
      )
    <?> "literal"

pattern' :: Parser Pattern
pattern' = choice
  [ PattLit <$> literal
  , PattParen <$> tokenParenOpen <*> pattern' <*> tokenParenClose
  , PattWildcard <$> tokenUnderscore
  , PattBinder <$> lower
  , PattConstructor <$> upper <*> many pattern'
  ]

--------------------------------------------------------------------------------
-- Type 
--------------------------------------------------------------------------------

type' :: Parser Type
type' = do
  result <- makeExprParser term table <?> "type"
  void $ many dedent
  return result
 where
  table :: [[Operator Parser Type]]
  table = [[InfixR function]]

  function :: Parser (Type -> Type -> Type)
  function = do
    -- an <indent> will be inserted after an <arrow>
    arrow <- tokenArrow
    indent
    return $ \x y -> TFunc x arrow y

  term :: Parser Type
  term = parensType <|> array <|>
         try typeVar <|> try baseType <|>
         typeName <?> "type term"

  parensType :: Parser Type
  parensType = TParen <$> tokenParenOpen <*> type' <*> tokenParenClose


  typeVar :: Parser Type
  typeVar = TVar <$> lower

  baseType :: Parser Type
  baseType = do (uname, range) <- getRange upperName
                case uname of
                  "Int"  -> return $ TBase (TInt range)
                  "Bool" -> return $ TBase (TBool range)
                  "Char" -> return $ TBase (TChar range)
                  _ ->  mzero

  typeName :: Parser Type
  typeName = TCon <$> upper <*> many lower

  -- an <indent> will be inserted after an <of>
  array :: Parser Type
  array = TArray <$> tokenArray <*> interval <*> tokenOf <* indent <*> type'

  interval :: Parser Interval
  interval = Interval <$> endpointOpening <*> tokenRange <*> endpointClosing

  endpointOpening :: Parser EndpointOpen
  endpointOpening = choice
    [ IncludingOpening <$> tokenBracketOpen <*> expression
    , ExcludingOpening <$> tokenParenOpen <*> expression
    ]

  endpointClosing :: Parser EndpointClose
  endpointClosing = do
    expr <- expression
    choice
      [ IncludingClosing expr <$> tokenBracketClose
      , ExcludingClosing expr <$> tokenParenClose
      ]

--------------------------------------------------------------------------------

-- | Combinators
block :: Parser a -> Parser a
block parser = do
  ignore TokIndent <?> "indentation"
  result <- parser
  void $ optional (ignore TokDedent <?> "dedentation")
  return result

-- a block of indented stuff seperated by newlines
blockOf :: Parser a -> Parser [a]
blockOf parser = do
  ignore TokIndent <?> "indentation"
  result <- sepBy1 parser newlines
  void $ optional (ignore TokDedent <?> "dedentation")
  return result

block' :: (l -> x -> r -> y) -> Parser l -> Parser x -> Parser r -> Parser y
block' constructor open parser close = do
  a <- open
  _ <- symbol TokIndent <?> "indentation"
  b <- parser
  c <- choice
    [ do
      _ <- symbol TokDedent <?> "dedentation"
      close
    , close
    , do
          -- the fucked up case:
          --  the tokener is not capable of handling cases like "if True -> skip fi"
          --  because it's not possible to determine the number of `TokDedent` before `TokFi`
      c <- close
      _ <- symbol TokDedent <?> "dedentation"
      return c
    ]
  return $ constructor a b c

-- remove TokIndent/TokDedent before TokGuardBar
ordinaryBar :: Parser (Token "|")
ordinaryBar = do
  void $ many (ignoreP indentationRelated)
  tokenGuardBar

-- consumes 1 or more newlines
expectNewline :: Parser ()
expectNewline = do
  -- see if the latest accepcted token is TokNewline
  t <- lift getLastToken
  case t of
    Just TokNewline -> return ()
    _               -> void $ some (ignore TokNewline)

upperName :: Parser Text
upperName = extract p
 where
  p (TokUpperName s) = Just s
  p _                = Nothing

upper :: Parser Name
upper =
  withLoc (Name <$> upperName)
    <?> "identifier that starts with a uppercase letter"

lowerName :: Parser Text
lowerName = extract p
 where
  p (TokLowerName s) = Just s
  p _                = Nothing

lower :: Parser Name
lower =
  withLoc (Name <$> lowerName)
    <?> "identifier that starts with a lowercase letter"

identifier :: Parser Name
identifier =
  withLoc (choice [Name <$> lowerName, Name <$> upperName]) <?> "identifier"

integer :: Parser Int
integer = extract p <?> "integer"
 where
  p (TokInt s) = Just s
  p _          = Nothing

character :: Parser Char
character = extract p <?> "character"
 where
  p (TokChar c) = Just c
  p _           = Nothing