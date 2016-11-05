{-# LANGUAGE DeriveFunctor, DeriveFoldable, DeriveGeneric, DeriveTraversable #-}
{-# LANGUAGE TypeSynonymInstances, FlexibleInstances #-}
module Graph (
    Graph, empty, vertex, overlay, connect, (~>), clique, vertices, normalise,
    fromRelation, simplify
    ) where

import Control.Monad.Reader
import Test.QuickCheck
import Text.PrettyPrint.HughesPJClass hiding (empty)

import PartialOrder
import Relation (Relation (..))
import qualified Relation

data Graph a = Empty
             | Vertex a
             | Overlay (Graph a) (Graph a)
             | Connect (Graph a) (Graph a)
             deriving (Show, Functor, Foldable, Traversable)

instance Arbitrary a => Arbitrary (Graph a) where
    arbitrary = sized graph
      where
        graph 0 = return Empty
        graph 1 = Vertex <$> arbitrary
        graph n = do
            left <- choose (0, n)
            oneof [ Overlay <$> (graph left) <*> (graph $ n - left)
                  , Connect <$> (graph left) <*> (graph $ n - left) ]

    shrink Empty         = []
    shrink (Vertex    _) = [Empty]
    shrink (Overlay x y) = [Empty, x, y]
                        ++ [Overlay x' y' | (x', y') <- shrink (x, y) ]
    shrink (Connect x y) = [Empty, x, y, Overlay x y]
                        ++ [Connect x' y' | (x', y') <- shrink (x, y) ]

instance Monoid (Graph a) where
    mempty  = Empty
    mappend = Overlay

instance Monoid (Reader a (Graph b)) where
    mempty  = return mempty
    mappend = liftM2 overlay

(~>) :: Graph a -> Graph a -> Graph a
(~>) = connect

instance Num a => Num (Graph a) where
    fromInteger = Vertex . fromInteger
    (+)         = Overlay
    (*)         = Connect
    signum      = const Empty
    abs         = id
    negate      = id

empty :: Graph a
empty = Empty

vertex :: a -> Graph a
vertex = Vertex

overlay :: Graph a -> Graph a -> Graph a
overlay = Overlay

connect :: Graph a -> Graph a -> Graph a
connect = Connect

vertices :: [a] -> Graph a
vertices = foldr Overlay Empty . map Vertex

clique :: [a] -> Graph a
clique = foldr Connect Empty . map Vertex

foldGraph :: b -> (a -> b) -> (b -> b -> b) -> (b -> b -> b) -> Graph a -> b
foldGraph e v o c = go
  where
    go Empty         = e
    go (Vertex  x  ) = v x
    go (Overlay x y) = o (go x) (go y)
    go (Connect x y) = c (go x) (go y)

fromRelation :: Relation a -> Graph a
fromRelation r = vertices (Relation.domain r) `Overlay` arcs
  where
    arcs = foldr Overlay Empty
        [ Vertex x `Connect` Vertex y | (x, y) <- Relation.relation r ]

normalise :: Ord a => Graph a -> Relation a
normalise = foldGraph Relation.empty Relation.singleton Relation.union cross
  where
    cross x y = Relation.unions [x, y, Relation.complete (domain x) (domain y)]

instance Ord a => Eq (Graph a) where
    x == y = normalise x == normalise y

instance Ord a => PartialOrder (Graph a) where
    x -<- y = normalise x -<- normalise y

instance Pretty a => Pretty (Graph a) where
    pPrintPrec _ _ Empty         = text "()"
    pPrintPrec _ _ (Vertex  x  ) = pPrint x
    pPrintPrec l p (Overlay x y) = maybeParens (p > 0) $
        hsep [pPrintPrec l 0 x, text "+", pPrintPrec l 0 y]
    pPrintPrec l _ (Connect x y) =
        hsep [pPrintPrec l 1 x, text "->", pPrintPrec l 1 y]

simplify :: Ord a => Graph a -> Graph a
simplify (Overlay x y)
    | x' -<- y' = y'
    | x' ->- y' = x'
    | otherwise = Overlay x' y'
  where
    x' = simplify x
    y' = simplify y
simplify (Connect x y)
    | x' == Empty = y'
    | y' == Empty = x'
    | otherwise = Connect x' y'
  where
    x' = simplify x
    y' = simplify y
simplify x = x
