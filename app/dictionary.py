from __future__ import annotations
from typing import Optional, Set

# Minimal Scrabble dictionary service for development/demo.
# In production, back this with PostgreSQL dictionary_words or a large word list.

DEFAULT_WORDS = {
    # Common short words (2-3 letters)
    'AA','AB','AD','AE','AG','AH','AI','AL','AM','AN','AR','AS','AT','AW','AX','AY',
    'BA','BE','BI','BO','BY',
    'DO','ED','EF','EH','EL','EM','EN','ER','ES','ET','EX',
    'FA','GO','HA','HE','HI','HM','HO','ID','IF','IN','IS','IT','JO','KA','KI','LA','LI','LO',
    'MA','ME','MI','MM','MO','MU','MY','NA','NE','NO','NU','OD','OE','OF','OH','OI','OM','ON','OP','OR','OS','OW','OX','OY',
    'PA','PE','PI','QI','RE','SH','SI','SO','TA','TI','TO','UH','UM','UN','UP','US','UT','WE','WO','XI','XU','YA','YE','YO',
    # Some 4-7 letter common words
    'HELLO','WORLD','SCRABBLE','TILE','BOARD','WORD','PLAY','GAME','POINT','QUIZ','JAZZ','FUZZ','PUZZLE','BLANK',
    'CAT','DOG','FISH','BIRD','HOUSE','MOUSE','TABLE','CHAIR','ZOO','ECHO','RHYTHM',
}

class DictionaryService:
    def __init__(self, words: Optional[Set[str]] = None):
        # Store uppercase words
        self._words: Set[str] = {w.upper() for w in (words or DEFAULT_WORDS)}

    def is_valid(self, word: str) -> bool:
        if not word:
            return False
        return word.upper() in self._words

    def definition(self, word: str) -> Optional[str]:
        # Demo placeholder; a real implementation would query a dictionary API or DB
        w = word.upper()
        if w in self._words:
            return f"Demo definition for {w}."
        return None

# Singleton instance
service = DictionaryService()
