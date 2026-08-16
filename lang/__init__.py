"""Language catalogues, one module per language.

To add a language: copy en.py, translate it, and add it to CATALOGUES below.
Nothing else in the codebase needs to change. i18n.catalogue() fills anything
you leave out from English, so a half-finished translation still renders.

Each module provides four names:

  STRINGS        the short labels. "date" is a strftime format and "decimal"
                 is the separator for temperatures. Numeric date formats only:
                 month names would mean another table per language, for no gain
                 on a panel where the weekday is the part people read.
  WEEKDAYS       seven short names, Monday first, to match date.weekday().
  WEEKDAYS_LONG  the same seven spelled out, for the header.
  WMO            weather code -> (full label, short label). The short form has
                 to fit a 184px column at 20px, so it collapses intensity:
                 "Heavy drizzle" and "Drizzle" both read "Drizzle" three days
                 out.

Plain dicts rather than gettext: these are ~20 short strings and a .po
toolchain would be more machinery than the problem deserves.
"""

from . import de, en

CATALOGUES = {"en": en, "de": de}
