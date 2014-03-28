module Language.MaroKani.Eval (eval, eval') where

import Language.MaroKani.Types
import Language.MaroKani.Prim
import Language.MaroKani.Parser
import Control.Monad
import Control.Monad.Trans
import Control.Monad.Catch
import Control.Applicative
import Control.Concurrent.STM
import Control.Concurrent.Async
import qualified Data.Map as M
import qualified Data.Vector as V
import Text.PrettyPrint.ANSI.Leijen (plain)

-- 同じ型をたくさん書いていて冗長

apply :: (MonadIO m, MonadCatch m) => Env -> TChan String -> Value -> Value -> m Value
apply env chan (Fun (Just fenv') name body) x = do
  fenv <- liftIO $ atomically $ newTVar $ M.insert name (Left x) fenv'
  eval fenv chan body
apply _ _ (Fun Nothing name body) x = throwM $ Default "Fun Nothing"
apply _ chan (PrimFun f) x = liftIO $ f x chan
apply _ _ f _ = throwM $ TypeMismatch "fun" "fun"

evalF :: (MonadIO m, MonadCatch m) => Env -> TChan String -> Expr -> m Value
evalF env chan (Var name) = do
  result <- liftIO $ atomically $ do
    env' <- readTVar env
    case M.lookup name env' of
      Nothing -> return Nothing
      Just (Left val) -> return $ Just val
      Just (Right ref) -> Just <$> readTVar ref
  case result of
    Nothing -> throwM $ UnknownName name
    Just val -> return val
evalF env chan (EValue (Fun Nothing name expr)) = do
  env' <- liftIO $ atomically $ readTVar env
  return $ Fun (Just env') name expr
evalF env chan (EValue val) = return val
evalF env chan (EArray exprs) = liftM (VArray . V.fromList) $ mapM (evalF env chan) exprs
evalF env chan (App e1 e2) = do
  v1 <- evalF env chan e1
  v2 <- evalF env chan e2
  apply env chan v1 v2
evalF env chan (Asgn name expr) = do
  val <- evalF env chan expr
  result <- liftIO $ atomically $ do
    env' <- readTVar env
    case M.lookup name env' of
      Just (Right ref) -> writeTVar ref val >> return True
      _ -> return False
  if result
    then return val
    else throwM $ UnknownName name
evalF env chan (If cond tru fls) = do
  cond' <- evalF env chan cond
  let tru' = evalF env chan tru
  let fls' = maybe (return $ VBool False) (evalF env chan) fls
  if isTrue cond' then tru' else fls'
evalF env chan (Decl name expr) = do
  val <- evalF env chan expr
  liftIO $ atomically $ do
    env' <- readTVar env
    ref <- newTVar val
    writeTVar env (M.insert name (Right ref) env')
  return val

eval :: (MonadIO m, MonadCatch m) => Env -> TChan String -> [Expr] -> m Value
eval env chan exprs = foldM (\_ e -> evalF env chan e) (VBool False) exprs

eval' :: (MonadIO m, MonadCatch m) => Env -> TChan String -> [Expr] -> m Value
eval' env chan exprs = do
  let Success std' = parse std
  eval env chan std'
  eval env chan exprs
