// D transliteration of FLTK's test/shadow_variables.cxx.
// Build: rdmd buildsamples.d test shadow_variables
//
// FLTK's version is just `#include "include_all.h"` (a CMake-generated
// header that #includes every public FLTK header, purely to check they all
// compile standalone/with -Wshadow) plus a trivial main(). The D equivalent
// is simply importing the package aggregator plus an empty main(); this one
// stays minimal rather than inventing something elaborate.
import fl;

void main()
{
}
