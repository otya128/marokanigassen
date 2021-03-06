module Language.MaroKani.Prim (newEnv, std) where

import Language.MaroKani.Types
import Data.Traversable (traverse)
import Control.Monad.Trans
import Control.Monad.Catch
import Control.Applicative
import Control.Concurrent.STM
import qualified Data.Map as M
import qualified Data.Vector as V
import qualified System.Random as Rand

mk1Arg :: (String -> Value -> IO Value) -> String -> (String,Value)
mk1Arg f name = (name, PrimFun $ \_ v _ -> f name v)

mk2Args :: (String -> Value -> Value -> IO Value) -> String -> (String,Value)
mk2Args f name = (name, PrimFun $ \_ x _ -> return $ PrimFun $ \_ y _ -> f name x y)

mk2Args' :: (String -> ([Expr] -> IO Value) -> Value -> Value -> IO Value) -> String -> (String,Value)
mk2Args' f name = (name, PrimFun $ \_ x _ -> return $ PrimFun $ \ev y _ -> f name ev x y)

calcNum :: (Integer -> Integer -> ti) -> (Double -> Double -> td)
  -> (ti -> a) -> (td -> a) -> Value -> Value -> String -> IO a
calcNum i _ c _ (VInt x) (VInt y) _ = return $ c $ x `i` y
calcNum _ d _ c (VInt x) (VDouble y) _ = return $ c $ fromIntegral x `d` y
calcNum _ d _ c (VDouble x) (VInt y) _ = return $ c $ x `d` fromIntegral y
calcNum _ d _ c (VDouble x) (VDouble y) _ = return $ c $ x `d` y
calcNum _ _ _ _ (VInt _) y s = throwM $ TypeMismatch (intName `typeOr` doubleName) (showType y) s
calcNum _ _ _ _ (VDouble _) y s = throwM $ TypeMismatch (intName `typeOr` doubleName) (showType y) s
calcNum _ _ _ _ x _ s = throwM $ TypeMismatch (intName `typeOr` doubleName) (showType x) s

primAdd :: String -> Value -> Value -> IO Value
primAdd _ (VString x) (VString y) = return $ VString $ x ++ y
primAdd name (VString _) y = throwM $ TypeMismatch stringName (showType y) name
primAdd name x (VString _) = throwM $ TypeMismatch stringName (showType x) name
primAdd name x y = calcNum (+) (+) VInt VDouble x y name
primSub :: String -> Value -> Value -> IO Value
primSub name x y = calcNum (-) (-) VInt VDouble x y name
primMul :: String -> Value -> Value -> IO Value
primMul name x y = calcNum (*) (*) VInt VDouble x y name
primDiv :: String -> Value -> Value -> IO Value
primDiv name x y = calcNum div (/) VInt VDouble x y name
primMod :: String -> Value -> Value -> IO Value
primMod _ (VInt x) (VInt y) = return $ VInt $ x `mod` y
primMod name (VInt _) y = throwM $ TypeMismatch intName (showType y) name
primMod name x _ = throwM $ TypeMismatch intName (showType x) name
primPow :: String -> Value -> Value -> IO Value
primPow name x y = calcNum (^) (**) VInt VDouble x y name
primLT :: String -> Value -> Value -> IO Value
primLT name x y = calcNum (<) (<) VBool VBool x y name
primLE :: String -> Value -> Value -> IO Value
primLE name x y = calcNum (<=) (<=) VBool VBool x y name
primGT :: String -> Value -> Value -> IO Value
primGT name x y = calcNum (>) (>) VBool VBool x y name
primGE :: String -> Value -> Value -> IO Value
primGE name x y = calcNum (>=) (>=) VBool VBool x y name
primNE :: String -> Value -> Value -> IO Value
primNE _ x y = return $ VBool $ x /= y
primEQ :: String -> Value -> Value -> IO Value
primEQ _ x y = return $ VBool $ x == y

primIndex :: String -> Value -> Value -> IO Value
primIndex _ (VArray arr) (VInt i) = return $ arr V.! fromIntegral i
primIndex _ (VString s) (VInt i) = return $ VString $ take 1 $ drop (fromIntegral i) s
primIndex name (VArray _) i = throwM $ TypeMismatch intName (showType i) name
primIndex name (VString _) i = throwM $ TypeMismatch intName (showType i) name
primIndex name a _ = throwM $ TypeMismatch (stringName `typeOr` arrayName) (showType a) name

primEnumFromTo :: String -> Value -> Value -> IO Value
primEnumFromTo name x y = calcNum V.enumFromTo V.enumFromTo
  (VArray . V.map VInt) (VArray . V.map VDouble) x y name

primHas :: String -> Value -> Value -> IO Value
primHas _ (VObject obj) (VString name) = return $ VBool $ M.member name obj
primHas name (VObject _) y = throwM $ TypeMismatch stringName (showType y) name
primHas name x _ = throwM $ TypeMismatch objectName (showType x) name

primMap :: String -> ([Expr] -> IO Value) -> Value -> Value -> IO Value
primMap _ ev f (VArray arr) = VArray <$> traverse (\v -> ev [App (EValue f) (EValue v)]) arr
primMap name _ _ y = throwM $ TypeMismatch arrayName (showType y) name

primPrint :: Value -> Output -> IO Value
primPrint x o = do
  s <- showIO x
  appendOutput o s
  return x

primTostr :: String -> Value -> IO Value
primTostr _ x = VString <$> showIO x

primShowFun :: String -> Value -> IO Value
primShowFun _ (Fun _ name es) = return $ VString $ "\\" ++ name ++ show es
primShowFun name f = throwM $ TypeMismatch funName (showType f) name

primRandInt :: String -> Value -> IO Value
primRandInt _ _ = VInt <$> Rand.randomIO

primCopy :: String -> Value -> IO Value
primCopy _ (VObject obj) = do
  let copy (Left v) = return $ Left v
      copy (Right ref) = readTVar ref >>= newTVar >>= return . Right
  newObj <- atomically $ traverse copy obj
  return $ VObject newObj
primCopy name x = throwM $ TypeMismatch objectName (showType x) name

primSin :: String -> Value -> IO Value
primSin _ (VDouble d) = return $ VDouble $ sin d
primSin _ (VInt i) = return $ VDouble $ sin $ fromIntegral i
primSin name x = throwM $ TypeMismatch doubleName (showType x) name

primCos :: String -> Value -> IO Value
primCos _ (VDouble d) = return $ VDouble $ cos d
primCos _ (VInt i) = return $ VDouble $ cos $ fromIntegral i
primCos name x = throwM $ TypeMismatch doubleName (showType x) name

primTan :: String -> Value -> IO Value
primTan _ (VDouble d) = return $ VDouble $ tan d
primTan _ (VInt i) = return $ VDouble $ tan $ fromIntegral i
primTan name x = throwM $ TypeMismatch doubleName (showType x) name

primFloor :: String -> Value -> IO Value
primFloor _ (VDouble d) = return $ VInt $ floor d
primFloor _ (VInt i) = return $ VInt i
primFloor name x = throwM $ TypeMismatch doubleName (showType x) name

primUnaryPlus :: String -> Value -> IO Value
primUnaryPlus _ (VInt i) = return $ VInt i
primUnaryPlus _ (VDouble d) = return $ VDouble d
primUnaryPlus name x = throwM $ TypeMismatch (intName `typeOr` doubleName) (showType x) name

primUnaryMinus :: String -> Value -> IO Value
primUnaryMinus _ (VInt i) = return $ VInt (- i)
primUnaryMinus _ (VDouble d) = return $ VDouble (- d)
primUnaryMinus name x = throwM $ TypeMismatch (intName `typeOr` doubleName) (showType x) name

primsList :: [(String,Value)]
primsList =
  [ ("true", VBool True)
  , ("false", VBool False)
  , ("pi", VDouble pi)
  , ("π", VDouble pi)
  , ("print", PrimFun $ \_ -> primPrint)
  , mk1Arg primTostr "tostr"
  , mk1Arg primShowFun "showFun"
  , mk1Arg primRandInt "randInt"
  , mk1Arg primCopy "copy"
  , mk1Arg primFloor "floor"
  , mk1Arg primSin "sin"
  , mk1Arg primCos "cos"
  , mk1Arg primTan "tan"
  , mk1Arg primUnaryPlus "[+]"
  , mk1Arg primUnaryMinus "[-]"
  , mk2Args primAdd "(+)"
  , mk2Args primSub "(-)"
  , mk2Args primMul "(*)"
  , mk2Args primDiv "(/)"
  , mk2Args primMod "(%)"
  , mk2Args primPow "(^)"
  , mk2Args primLT "(<)"
  , mk2Args primLE "(<=)"
  , mk2Args primGT "(>)"
  , mk2Args primGE "(>=)"
  , mk2Args primNE "(!=)"
  , mk2Args primEQ "(==)"
  , mk2Args primIndex "(!)"
  , mk2Args primEnumFromTo "(--->)"
  , mk2Args primHas "has"
  , mk2Args' primMap "map"
  ]

newEnv :: MonadIO m => m Env
newEnv = liftIO $ do
  atomically $ newTVar $ M.map Left $ M.fromList primsList

std :: String
std
  =  "If ::= \\b x y {if b then x else y};"
  ++ "(<<) ::= \\f g x {f (g x)};"
  ++ "(>>) ::= \\f g x {g (f x)};"
  ++ "($) ::= \\f x {f x};"
  ++ "(&&) ::= \\x y {if x then y else x};"
  ++ "(||) ::= \\x y {if x then x else y};"
  ++ "[!] ::= \\x {if x then false else true};"
  ++ "fix ::= \\f { \\x{f(\\y{x x y})} \\x{f(\\y{x x y})} };"
