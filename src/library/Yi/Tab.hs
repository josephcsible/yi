{-# LANGUAGE DeriveDataTypeable #-}
{-# LANGUAGE Rank2Types #-}

module Yi.Tab
 (
  Tab,
  TabRef,
  tabWindowsA,
  tabLayoutManagerA,
  tabDividerPositionA,
  tkey,
  tabMiniWindows,
  tabFocus,
  forceTab,
  mapWindows,
  tabLayout,
  tabFoldl,
  makeTab,
  makeTab1,
 )  where

import Prelude hiding (foldr, foldl)

import Control.Lens ( Lens', (^.), lens, over )
import qualified Data.Binary as Binary ( get, put, Binary )
import Data.Default ( def )
import Data.Typeable ( Typeable )
import Data.Foldable ( foldl, foldr, toList )
import qualified Data.List.PointedList as PL
    ( PointedList, _focus, singleton )
import Control.Applicative ( (<$>), (<*>) )
import Yi.Buffer.Basic ( WindowRef )
import Yi.Layout
    ( AnyLayoutManager,
      DividerPosition,
      DividerRef,
      dividerPositionA,
      Layout,
      pureLayout )
import Yi.Window ( Window, isMini, wkey )

type TabRef = Int

-- | A tab, containing a collection of windows.
data Tab = Tab {
  tkey             :: !TabRef,                  -- ^ For UI sync; fixes #304
  tabWindows       :: !(PL.PointedList Window), -- ^ Visible windows
  tabLayout        :: !(Layout WindowRef),      -- ^ Current layout. Invariant: must be the layout generated by 'tabLayoutManager', up to changing the 'divPos's.
  tabLayoutManager :: !AnyLayoutManager -- ^ layout manager (for regenerating the layout when we add/remove windows)
  }
 deriving Typeable

tabFocus :: Tab -> Window
tabFocus = PL._focus . tabWindows

-- | Returns a list of all mini windows associated with the given tab
tabMiniWindows :: Tab -> [Window]
tabMiniWindows = Prelude.filter isMini . toList . tabWindows

-- | Accessor for the windows. If the windows (but not the focus) have changed when setting, then a relayout will be triggered to preserve the internal invariant.
tabWindowsA :: Functor f =>
    (PL.PointedList Window -> f (PL.PointedList Window)) -> Tab -> f Tab
tabWindowsA f s = (`setter` s) <$> f (getter s)
  where
    setter ws t = relayoutIf (toList ws /= toList (tabWindows t)) (t { tabWindows = ws})
    getter = tabWindows

-- | Accessor for the layout manager. When setting, will trigger a relayout if the layout manager has changed.
tabLayoutManagerA :: Functor f =>
    (AnyLayoutManager -> f AnyLayoutManager) -> Tab -> f Tab
tabLayoutManagerA f s = (`setter` s) <$> f (getter s)
  where
    setter lm t = relayoutIf (lm /= tabLayoutManager t) (t { tabLayoutManager = lm })
    getter = tabLayoutManager

-- | Gets / sets the position of the divider with the given reference. The caller must ensure that the DividerRef is valid, otherwise an error will (might!) occur.
tabDividerPositionA :: DividerRef -> Lens' Tab DividerPosition
tabDividerPositionA ref = lens tabLayout (\ t l -> t{tabLayout = l}) . dividerPositionA ref

relayoutIf :: Bool -> Tab -> Tab
relayoutIf False t = t
relayoutIf True t = relayout t

relayout :: Tab -> Tab
relayout t = t { tabLayout = buildLayout (tabWindows t) (tabLayoutManager t) (tabLayout t) }

instance Binary.Binary Tab where
  put (Tab tk ws _ _) = Binary.put tk >> Binary.put ws
  get = makeTab <$> Binary.get <*> Binary.get


-- | Equality on tab identity (the 'tkey')
instance Eq Tab where
  (==) t1 t2 = tkey t1 == tkey t2

instance Show Tab where
  show t = "Tab " ++ show (tkey t)

-- | A specialised version of "fmap".
mapWindows :: (Window -> Window) -> Tab -> Tab
mapWindows f = over tabWindowsA (fmap f)

-- | Forces all windows in the tab
forceTab :: Tab -> Tab
forceTab t = foldr seq t (t ^. tabWindowsA)

-- | Folds over the windows in the tab
tabFoldl :: (a -> Window -> a) -> a -> Tab -> a
tabFoldl f z t = foldl f z (t ^. tabWindowsA)

-- | Run the layout on the given tab, for the given aspect ratio
buildLayout :: PL.PointedList Window -> AnyLayoutManager -> Layout WindowRef -> Layout WindowRef
buildLayout ws m l = pureLayout m l . fmap wkey . Prelude.filter (not . isMini) . toList $ ws

-- | Make a tab from multiple windows
makeTab :: TabRef -> PL.PointedList Window -> Tab
makeTab key ws = Tab key ws (buildLayout ws def def) def

-- | Make a tab from one window
makeTab1 :: TabRef -> Window -> Tab
makeTab1 key win = makeTab key (PL.singleton win)
