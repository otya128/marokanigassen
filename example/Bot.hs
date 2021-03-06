import Network.MaroKani
import Network.MaroKani.Bot
import qualified Language.Calc as Calc
import qualified Language.MaroKani as MaroKani

import Control.Monad
import Control.Monad.Trans
import Control.Monad.Catch
import Control.Applicative

actions :: [Script]
actions =
  [ colonsEnd (not <$> isSelf) ["m","cal"] $ \code -> void $ do
    let s = either to2byteSpace (("res: " ++) . show) $ Calc.run code
    say s
  , colonsEnd (not <$> isSelf) ["m","m"] $ \code -> void $ do
    s <- liftIO $ catch (MaroKani.run (Just 2) (Just 512) code) tostr
    let s' = if null s then "(empty)" else s
    liftIO $ putStrLn s'
    say s'
  , colonsEnd (not <$> isSelf) ["m","parse"] $ \code -> void $ do
    s <- liftIO $ catch (show <$> MaroKani.parseIO code) tostr
    say s
  , colonsSep isOwner ["m","cmd"] "exit" $ void exit
  , colonsSep isOwner ["m","cmd"] "enter" $ void enter
  , colonsSep isOwner ["m","cmd","delete"] "all" $ void deleteAll
  , colonsEnd (not <$> isSelf) ["m","cmd","delete"] $ \n -> void $
    case reads n of
      [(n',"")] -> delete n'
      _ -> say "parser error"
  ]
  where
    to2byteSpace (' ':' ':' ':' ':xs) = "　 " ++ to2byteSpace xs
    to2byteSpace (' ':' ':xs) = "　" ++ to2byteSpace xs
    to2byteSpace (x:xs) = x : to2byteSpace xs
    to2byteSpace "" = ""
    tostr :: MaroKani.MaroKaniException -> IO String
    tostr = return . to2byteSpace . show

reacts :: KaniResponse -> Kani ()
reacts = mkReacts actions

bot :: String -> String -> String -> IO ()
bot name roomId trip = do
  let config = defaultConfig
  let req = (defaultRequest name roomId) { reqTrip = Just trip }
  runKani config req $ do
    res <- newId
    liftIO $ putStrLn $ resSessionId res
    soon_
    let loop = do
          comet >>= reacts
          loop
    loop

botId :: String -> String -> String -> String -> IO ()
botId name roomId trip sId = do
  let config = defaultConfig
  let req = (defaultRequest name roomId) { reqTrip = Just trip, reqId = Just sId }
  runKani config req $ do
    liftIO $ putStrLn sId
    soon_
    let loop = do
          comet >>= reacts
          loop
    loop

main :: IO ()
main = do
  t <- getLine
  s <- getLine
  if null s
    then bot "λまろろろ" "petcwiki" t
    else botId "λまろろろ" "petcwiki" t s
