// D transliteration of FLTK's test/shadow_variables.cxx (~/Repositories/fltk).
// Part of the samples/ contract -- see samples/README.md.
// Check: ./samples/build.sh shadow_variables
//
// FLTK's version is just `#include "include_all.h"` (a CMake-generated
// header that #includes every public FLTK header, purely to check they all
// compile standalone/with -Wshadow) plus a trivial main(). The D equivalent
// is simply importing the package aggregator plus an empty main() -- see
// the task note in samples/README.md/CLAUDE.md for why this one stays
// minimal rather than inventing something elaborate.
import fl;

void main()
{
}
