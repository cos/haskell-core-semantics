{-# LANGUAGE UnicodeSyntax #-}

module Main where

import qualified BasicTypes
import           Control.Monad      ((<=<))
import           CoreSyn
import           Data.List          (concat, intercalate)
import           DynFlags           (defaultLogAction, ghcMode)
import           GHC
import           GHC.Paths          (libdir)
import           HscTypes           (mg_binds)
import           Literal
import qualified Name
import qualified Outputable         as OP
import           System.Environment
import           TyCon
import           TyCoRep            (Coercion (..), TyBinder (..), Type (..))
import qualified Unique             as U
import           Var

args :: [String] -> String
args ss = "(" ++ intercalate "; " ss ++ ")"

outVar :: CoreBndr -> String
outVar = show . U.getUnique

outTyVar :: TyBinder -> String
outTyVar (Named tyvar vf) = show $ U.getUnique tyvar
outTyVar (Anon ty)        = prType ty

prList :: [String] -> String
prList = intercalate "::"

prTyCon :: TyCon -> String
prTyCon tc
  | isFunTyCon tc = "arrTyCon"
  | isAlgTyCon tc = "algTyCon" ++ "{" ++ prType (tyConKind tc) ++ "}"
  | isTypeSynonymTyCon tc = "synTyCon" ++ "{" ++ prType (tyConKind tc) ++ "}"
  | isTupleTyCon tc = "tupleTyCon" ++ "{" ++ prType (tyConKind tc) ++ "}"
  | isPrimTyCon tc = "primTyCon()"
  | isPromotedDataCon tc = "promDataCon()"

prCoercion :: Coercion -> String
prCoercion = error "TODO"

prType :: Type -> String
prType (TyVarTy x) =
  outVar x
prType (AppTy ty1 ty2)  =
  "appTy" ++ args [prType ty1, prType ty2]
prType (TyConApp tc kt) =
  "tyConApp" ++ args [prList (prType <$> kt)]
prType (ForAllTy (Named tyvar vf) ty) =
  "forallTy" ++ args [show (U.getUnique tyvar) ++ "." ++ prType ty]
prType (ForAllTy (Anon ty1) ty2) =
  "arr" ++ args [prType ty1, prType ty2]
prType (LitTy tyl) =
  OP.showSDocUnsafe (OP.ppr tyl)
prType (CastTy ty kindco) = error "TODO"
  -- "castTy" ++ (args (prType <$> [ty, kind]))
prType (CoercionTy co) = error "TODO: CoercionTy case of prType."

prExpr :: CoreExpr -> String
prExpr v@(Var x) = show $ U.getUnique x
prExpr l@(Lit a) = "lit" ++ "[" ++ OP.showSDocUnsafe (OP.ppr l) ++ "]"
prExpr (App e1 e2) = "app" ++ args (prExpr <$> [e1, e2])
prExpr (Lam x e) = "lam" ++ args [show (U.getUnique x) ++ "." ++ prExpr e]
prExpr (Let (Rec []) e2) = prExpr e2
prExpr (Let (Rec ((b, e1):bs)) e2) =
  let rest = prExpr (Let (Rec bs) e2) in
    "letrec" ++ args [prExpr e1, outVar b ++ "." ++ rest]
prExpr (Let (NonRec b e1) e2) =
    "let" ++ args [prExpr e1, (show . U.getUnique $ b) ++ "." ++ prExpr e2]
prExpr (Case e b ty alts)  =
    "case" ++ args [prExpr e, outVar b, prType ty, "altsTODO"]
prExpr (Cast e co) = "coerce" ++ args [prExpr e]
prExpr (Tick t e) = error "TODO: Tick case of prExpr."
prExpr (Type ty) = prType ty
prExpr (Coercion co) = error "TODO: Coercion case of prExpr."

prettyDecl :: (CoreBndr, Expr CoreBndr) -> String
prettyDecl (b, e) = outVar b ++ "." ++ prExpr e

prBind :: CoreBind -> String
prBind (NonRec x e) = "decl" ++ args [show (U.getUnique x), prExpr e]
prBind (Rec bs)     = "declRec" ++ args (prettyDecl <$> bs)

compileToCore :: String -> IO [CoreBind]
compileToCore modName = runGhc (Just libdir) $ do
    setSessionDynFlags =<< getSessionDynFlags
    target <- guessTarget (modName ++ ".hs") Nothing
    setTargets [target]
    load LoadAllTargets
    ds <- desugarModule <=< typecheckModule <=< parseModule <=< getModSummary $ mkModuleName modName
    return $ mg_binds . coreModule $ ds

main :: IO ()
main = do
  args <- getArgs
  c <- compileToCore (head args)
  mapM_ (putStrLn . prBind) c