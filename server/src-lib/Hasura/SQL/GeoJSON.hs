{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE LambdaCase                 #-}
{-# LANGUAGE OverloadedStrings          #-}

module Hasura.SQL.GeoJSON
  ( Point(..)
  , MultiPoint(..)
  , LineString(..)
  , MultiLineString(..)
  , Polygon(..)
  , MultiPolygon(..)
  , GeometryCollection(..)
  , Geometry(..)
  ) where

import qualified Data.Aeson       as J
import qualified Data.Aeson.Types as J
import qualified Data.Text        as T
import qualified Data.Vector      as V

import           Control.Monad
import           Data.Maybe       (maybeToList)
import           Hasura.Prelude

data Position
  = Position !Double !Double !(Maybe Double)
  deriving (Show, Eq)

withParsedArray
  :: (J.FromJSON a)
  => String -> (V.Vector a -> J.Parser b) -> J.Value -> J.Parser b
withParsedArray s fn =
  J.withArray s (mapM J.parseJSON >=> fn)

instance J.FromJSON Position where
  parseJSON = withParsedArray "Position" $ \arr ->
    if V.length arr < 2
    then fail "A Position needs at least 2 elements"
    -- here we are ignoring anything past 3 elements
    else return $ Position
         (arr `V.unsafeIndex` 0)
         (arr `V.unsafeIndex` 1)
         (arr V.!? 2)

instance J.ToJSON Position where
  toJSON (Position a b c)
    = J.toJSON $ a:b:maybeToList c

newtype Point
  = Point { unPoint :: Position }
  deriving (Show, Eq, J.ToJSON, J.FromJSON)

newtype MultiPoint
  = MultiPoint { unMultiPoint :: [Position] }
  deriving (Show, Eq, J.ToJSON, J.FromJSON)

data LineString
  = LineString
  { _lsFirst  :: !Position
  , _lsSecond :: !Position
  , _lsRest   :: ![Position]
  } deriving (Show, Eq)

instance J.ToJSON LineString where
  toJSON (LineString a b rest)
    = J.toJSON $ a:b:rest

instance J.FromJSON LineString where
  parseJSON = withParsedArray "LineString" $ \arr ->
    if V.length arr < 2
    then fail "A LineString needs at least 2 Positions"
    -- here we are ignoring anything past 3 elements
    else
      let fstPos = arr `V.unsafeIndex` 0
          sndPos = arr `V.unsafeIndex` 1
          rest   = V.toList $ V.drop 2 arr
      in return $ LineString fstPos sndPos rest

newtype MultiLineString
  = MultiLineString { unMultiLineString :: [LineString] }
  deriving (Show, Eq, J.ToJSON, J.FromJSON)

newtype GeometryCollection
  = GeometryCollection { unGeometryCollection :: [Geometry] }
  deriving (Show, Eq, J.ToJSON, J.FromJSON)

data LinearRing
  = LinearRing
  { _pFirst  :: !Position
  , _pSecond :: !Position
  , _pThird  :: !Position
  , _pRest   :: ![Position]
  } deriving (Show, Eq)

instance J.FromJSON LinearRing where
  parseJSON = withParsedArray "LinearRing" $ \arr ->
    if V.length arr < 4
    then fail "A LinearRing needs at least 4 Positions"
    -- here we are ignoring anything past 3 elements
    else do
      let fstPos = arr `V.unsafeIndex` 0
          sndPos = arr `V.unsafeIndex` 1
          thrPos = arr `V.unsafeIndex` 2
          rest   = V.drop 3 arr
      let lastPos = V.last rest
      unless (fstPos == lastPos) $
        fail "the first and last locations have to be equal for a LinearRing"
      return $ LinearRing fstPos sndPos thrPos $ V.toList $ V.init rest

instance J.ToJSON LinearRing where
  toJSON (LinearRing a b c rest)
    = J.toJSON $ (V.fromList [a, b, c] <> V.fromList rest) `V.snoc` a

newtype Polygon
  = Polygon { unPolygon :: [LinearRing] }
  deriving (Show, Eq, J.ToJSON, J.FromJSON)

newtype MultiPolygon
  = MultiPolygon { unMultiPolygon :: [Polygon] }
  deriving (Show, Eq, J.ToJSON, J.FromJSON)

data Geometry
  = GPoint !Point
  | GMultiPoint !MultiPoint
  | GLineString !LineString
  | GMultiLineString !MultiLineString
  | GPolygon !Polygon
  | GMultiPolygon !MultiPolygon
  | GGeometryCollection !GeometryCollection
  deriving (Show, Eq)

encToCoords :: (J.ToJSON a) => T.Text -> a -> J.Value
encToCoords ty a =
  J.object [ "type" J..= ty, "coordinates" J..= a]

instance J.ToJSON Geometry where
  toJSON = \case
    GPoint o              -> encToCoords "Point" o
    GMultiPoint o         -> encToCoords "MultiPoint" o
    GLineString o         -> encToCoords "LineString" o
    GMultiLineString o    -> encToCoords "MultiLineString" o
    GPolygon o            -> encToCoords "Polygon" o
    GMultiPolygon o       -> encToCoords "MultiPoylgon" o
    GGeometryCollection o ->
      J.object [ "type" J..= ("GeometryCollection"::T.Text)
               , "geometries" J..= o
               ]

instance J.FromJSON Geometry where
  parseJSON = J.withObject "Geometry" $ \o -> do
    ty <- o J..: "type"
    case ty of
      "Point"              -> GPoint      <$> o J..: "coordinates"
      "MultiPoint"         -> GMultiPoint <$> o J..: "coordinates"
      "LineString"         -> GLineString <$> o J..: "coordinates"
      "MultiLineString"    -> GMultiLineString <$> o J..: "coordinates"
      "Polygon"            -> GPolygon <$> o J..: "coordinates"
      "MultiPoylgon"       -> GMultiPolygon <$> o J..: "coordinates"
      "GeometryCollection" -> GGeometryCollection <$> o J..: "geometries"
      _                    -> fail $ "unexpected geometry type: " <> ty
